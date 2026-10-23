use reader_rust::{
    crawler::http_client::HttpClient, model::book::Book, parser::rule_engine::RuleEngine,
    service::book_service::BookService, storage::cache::file_cache::FileCache,
};

fn fixture() -> (BookService, std::path::PathBuf) {
    let root = std::env::temp_dir().join(format!("reader-sync-{}", uuid::Uuid::new_v4()));
    let service = BookService::new(
        HttpClient::new(5, None).unwrap(),
        RuleEngine::new().unwrap(),
        FileCache::new(root.join("cache")),
        root.to_str().unwrap(),
    );
    (service, root)
}

fn book(url: &str) -> Book {
    Book {
        name: "示例".into(),
        author: "作者".into(),
        origin: "local-txt".into(),
        book_url: url.into(),
        ..Default::default()
    }
}

#[tokio::test]
async fn stale_device_cannot_replace_newer_progress_or_hide_a_conflict() {
    let (service, root) = fixture();
    service.save_book("reader", book("book1")).await.unwrap();
    let first = service
        .sync_reading_progress("reader", "book1", 5, Some(3750), Some(0), None)
        .await
        .unwrap();
    assert!(first.accepted);
    let replay = service
        .sync_reading_progress("reader", "book1", 5, Some(3750), Some(0), None)
        .await
        .unwrap();
    assert!(replay.accepted);
    assert_eq!(replay.book.dur_chapter_time, first.book.dur_chapter_time);
    let stale = service
        .sync_reading_progress("reader", "book1", 1, Some(0), Some(0), None)
        .await
        .unwrap();
    assert!(!stale.accepted);
    assert_eq!(stale.book.dur_chapter_index, Some(5));
    assert_eq!(stale.book.dur_chapter_pos, Some(3750));
    let resolved = service
        .sync_reading_progress(
            "reader",
            "book1",
            1,
            Some(400),
            first.book.dur_chapter_time,
            None,
        )
        .await
        .unwrap();
    assert!(
        resolved.accepted,
        "explicitly choosing the local position must permit reading backwards"
    );
    assert!(resolved.book.dur_chapter_time > first.book.dur_chapter_time);
    tokio::fs::remove_dir_all(root).await.unwrap();
}

#[tokio::test]
async fn simultaneous_devices_have_one_winner_and_different_books_do_not_lose_updates() {
    let (service, root) = fixture();
    service
        .save_books("reader", vec![book("book1"), book("book2")])
        .await
        .unwrap();
    let (first, second) = tokio::join!(
        service.sync_reading_progress("reader", "book1", 2, Some(2000), Some(0), None),
        service.sync_reading_progress("reader", "book1", 3, Some(3000), Some(0), None),
    );
    assert_ne!(first.unwrap().accepted, second.unwrap().accepted);
    let (first, second) = tokio::join!(
        service.sync_reading_progress("reader", "book1", 7, Some(500), None, None),
        service.sync_reading_progress("reader", "book2", 9, Some(800), Some(0), None),
    );
    assert!(first.unwrap().accepted && second.unwrap().accepted);
    let books = service.get_bookshelf("reader").await.unwrap();
    assert_eq!(books[0].dur_chapter_index, Some(7));
    assert_eq!(books[1].dur_chapter_index, Some(9));
    tokio::fs::remove_dir_all(root).await.unwrap();
}

#[tokio::test]
async fn stale_shelf_reordering_preserves_progress_and_accounts_are_isolated() {
    let (service, root) = fixture();
    let snapshot = vec![book("book1")];
    service
        .save_books("reader", snapshot.clone())
        .await
        .unwrap();
    service.save_books("other", snapshot.clone()).await.unwrap();
    let saved = service
        .sync_reading_progress("reader", "book1", 4, Some(7500), Some(0), None)
        .await
        .unwrap();
    service.save_books("reader", snapshot).await.unwrap();
    let current = service
        .get_shelf_book("reader", "book1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(current.dur_chapter_time, saved.book.dur_chapter_time);
    assert_eq!(current.dur_chapter_index, Some(4));
    let other = service
        .get_shelf_book("other", "book1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(other.dur_chapter_index, None);
    assert!(service
        .sync_reading_progress("reader", "book1", -1, Some(0), None, None)
        .await
        .is_err());
    assert!(service
        .sync_reading_progress("reader", "book1", 0, Some(10001), None, None)
        .await
        .is_err());
    tokio::fs::remove_dir_all(root).await.unwrap();
}
