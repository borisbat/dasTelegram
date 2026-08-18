options gen2

require dastest/testing_boost public
require telegram_history_import

[test]
def test_telegram_export_parser(t : T?) {
    t |> run("timestamp honors the exported UTC offset") @(t : T?) {
        var epoch = 0l
        var error = ""
        t |> success(parse_telegram_export_timestamp(
            "14.06.2022 15:21:58 UTC-08:00", epoch, error), error)
        t |> equal(epoch, 1655248918l)
    }

    t |> run("joined messages inherit sender and preserve reply media and line breaks") @(t : T?) {
        let html = ("<!DOCTYPE html><html><body>" +
                    "<div class='message default clearfix' id='message1'>" +
                    "<div class='pull_right date details' title='14.06.2022 15:21:58 UTC-08:00'></div>" +
                    "<div class='from_name'>Alice</div>" +
                    "<div class='text'>Hello<br/>world</div></div>" +
                    "<div class='message default clearfix joined' id='message2'>" +
                    "<div class='pull_right date details' title='14.06.2022 15:22:58 UTC-08:00'></div>" +
                    "<div class='reply_to'><a href='#go_to_message1'>reply</a></div>" +
                    "<a href='voice_messages/audio_1.ogg'>voice</a>" +
                    "<div class='text'>Second</div></div>" +
                    "<div class='message service' id='message-3'><div class='text'>date</div></div>" +
                    "</body></html>")
        var sender = ""
        var error = ""
        let messages <- parse_telegram_export_page(html, sender, error)
        t |> equal(error, "")
        t |> equal(length(messages), 2)
        if (length(messages) == 2) {
            t |> equal(messages[0].SenderName, "Alice")
            t |> equal(messages[0].Text, "Hello\nworld")
            t |> equal(messages[1].SenderName, "Alice")
            t |> equal(messages[1].ReplyToMessageId, 1l)
            t |> equal(messages[1].MediaPath, "voice_messages/audio_1.ogg")
            t |> equal(messages[1].SourceKind, "imported_voice")
        }
        t |> success(telegram_export_sender_id("Alice") < 0l)
        t |> equal(telegram_export_sender_id(" Alice "), telegram_export_sender_id("alice"))
    }

    t |> run("invalid empty bot-button attribute is ignored") @(t : T?) {
        let html = ("<!DOCTYPE html><html><body>" +
                    "<div class='message default clearfix' id='message3'>" +
                    "<div class='pull_right date details' title='14.06.2022 15:21:58 UTC-08:00'></div>" +
                    "<div class='from_name'>Alice</div>" +
                    "<div class='text'><a =\"\" href='https://t.me/proxy'>Proxy</a></div></div>" +
                    "</body></html>")
        var sender = ""
        var error = ""
        let messages <- parse_telegram_export_page(html, sender, error)
        t |> equal(error, "")
        t |> equal(length(messages), 1)
        if (length(messages) == 1) {
            t |> equal(messages[0].Text, "Proxy")
        }
    }

    t |> run("one malformed timestamp does not discard the page") @(t : T?) {
        let html = ("<!DOCTYPE html><html><body>" +
                    "<div class='message default clearfix' id='message4'>" +
                    "<div class='pull_right date details' title='not a timestamp'></div>" +
                    "<div class='from_name'>Alice</div>" +
                    "<div class='text'>Broken date</div></div>" +
                    "<div class='message default clearfix joined' id='message5'>" +
                    "<div class='pull_right date details' title='14.06.2022 15:21:58 UTC-08:00'></div>" +
                    "<div class='text'>Valid date</div></div>" +
                    "</body></html>")
        var sender = ""
        var error = ""
        let messages <- parse_telegram_export_page(html, sender, error)
        t |> equal(error, "")
        t |> equal(length(messages), 2)
        if (length(messages) == 2) {
            t |> equal(messages[0].MessageDate, 0l)
            t |> equal(messages[1].MessageDate, 1655248918l)
        }
    }
}
