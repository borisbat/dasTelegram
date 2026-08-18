options gen2
options rtti
options no_unused_function_arguments = false

require dastest/testing_boost
require cadmus_web

[test]
def test_brave_percent_encode(t : T?) {
    t |> equal(brave_percent_encode("a b/?"), "a%20b%2F%3F")
    t |> equal(brave_percent_encode("К"), "%D0%9A")
}

[test]
def test_clean_brave_text(t : T?) {
    t |> equal(clean_brave_text("A <strong>bold</strong> &amp; <em>useful</em> result"),
               "A bold & useful result")
}

[test]
def test_parse_brave_search(t : T?) {
    let body = ("\{\"web\":\{\"results\":[" +
                "\{\"title\":\"One <strong>result</strong>\",\"url\":\"https://one.example/\"," +
                "\"description\":\"First &amp; best\"}," +
                "\{\"title\":\"Two\",\"url\":\"https://two.example/\",\"description\":\"Second\"}" +
                "]}}")
    var results : array<BraveSearchResult>
    var error = ""
    t |> success(parse_brave_search(body, 1, results, error), error)
    t |> equal(length(results), 1)
    if (length(results) == 1) {
        t |> equal(results[0].Title, "One result")
        t |> equal(results[0].Url, "https://one.example/")
        t |> equal(results[0].Description, "First & best")
    }
}

[test]
def test_append_brave_sources_deduplicates(t : T?) {
    let sources <- [
        BraveSearchResult(Title = "One", Url = "https://one.example/"),
        BraveSearchResult(Title = "Duplicate", Url = "https://one.example/"),
        BraveSearchResult(Title = "Two", Url = "https://two.example/")]
    let answer = append_brave_sources("Answer.", sources)
    t |> equal(answer,
               "Answer.\n\nSources:\n- One: https://one.example/\n- Two: https://two.example/\n")
}

[test]
def test_reply_urls_are_grounded(t : T?) {
    let allowed <- ["https://one.example/story", "http://two.example/"]
    t |> success(reply_urls_are_grounded("No links here.", allowed))
    t |> success(reply_urls_are_grounded(
        "Read [the source](https://one.example/story), please.", allowed))
    t |> success(reply_urls_are_grounded("Also http://two.example/.", allowed))
    t |> success(!reply_urls_are_grounded("Made up: https://fake.example/news", allowed))
    t |> success(!reply_urls_are_grounded("Made up: HTTPS://fake.example/news", allowed))
    t |> success(!reply_urls_are_grounded(
        "One real https://one.example/story and one fake https://fake.example/", allowed))
    t |> success(!reply_urls_are_grounded(
        "Invented child: https://one.example/story/not-returned", allowed))
    t |> success(!reply_urls_are_grounded("No sources: https://one.example/story", []))
}
