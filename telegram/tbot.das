options gen2
options indenting = 4
options rtti
options no_unused_block_arguments = false
options no_unused_function_arguments = false

module tbot shared private

require tbotapi public

require dashv/dashv_boost
require daslib/fio
require strings

struct public configuration {
    token : string
}

def public telegram_set_configuration(conf : configuration) {
    BOT_TOKEN = conf.token
}

var private BOT_TOKEN : string
var private LAST_ERROR = ""
var private LOG_API_CALLS = false

def public telegram_get_last_error() {
    //! return error made via last request
    return LAST_ERROR
}

def public telegram_set_log_api_calls(enable : bool) {
    LOG_API_CALLS = enable
}

// Extract the raw JSON substring for a top-level field value.
// e.g. json_extract_field("{\"ok\":true,\"result\":[1,2]}", "result") => "[1,2]"
def private json_extract_field(json : string implicit; field_name : string) : string {
    let needle = "\"{field_name}\":"
    let idx = find(json, needle)
    if (idx < 0) {
        return ""
    }
    var start = idx + length(needle)
    let len = length(json)
    // skip whitespace
    while (start < len) {
        let ch = unsafe(character_uat(json, start))
        if (ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r') {
            break
        }
        start++
    }
    if (start >= len) {
        return ""
    }
    let ch = unsafe(character_uat(json, start))
    if (ch == '{' || ch == '[') {
        // object or array — scan matching braces/brackets
        var depth = 1
        var in_string = false
        var escape_next = false
        var pos = start + 1
        while (pos < len && depth > 0) {
            let c = unsafe(character_uat(json, pos))
            if (escape_next) {
                escape_next = false
            } elif (c == '\\' && in_string) {
                escape_next = true
            } elif (c == '"') {
                in_string = !in_string
            } elif (!in_string) {
                if (c == '{' || c == '[') {
                    depth++
                } elif (c == '}' || c == ']') {
                    depth--
                }
            }
            pos++
        }
        return slice(json, start, pos)
    } elif (ch == '"') {
        // string — find closing quote
        var pos = start + 1
        while (pos < len) {
            let c = unsafe(character_uat(json, pos))
            if (c == '\\') {
                pos += 2
                continue
            }
            if (c == '"') {
                return slice(json, start, pos + 1)
            }
            pos++
        }
        return ""
    } else {
        // number, true, false, null — scan to delimiter
        var pos = start
        while (pos < len) {
            let c = unsafe(character_uat(json, pos))
            if (c == ',' || c == '}' || c == ']' || c == ' ' || c == '\n' || c == '\r' || c == '\t') {
                break
            }
            pos++
        }
        return slice(json, start, pos)
    }
}

def private telegram_call(METHOD : string; request : auto; var res : auto(RES_TYPE)) {
    let body = sprint_json(request, false)
    let url = "https://api.telegram.org/bot{BOT_TOKEN}/{METHOD}"
    LAST_ERROR = ""
    if (LOG_API_CALLS) {
        to_log(LOG_INFO, "API CALL: {url}\n")
    }
    POST(url, body, { "Content-Type" => "application/json" }) $(resp) {
        if (resp.status_code == http_status.OK) {
            peek(resp.body) $(text) {
                let ok_val = json_extract_field(text, "ok")
                if (ok_val == "true") {
                    let result_json = json_extract_field(text, "result")
                    if (!empty(result_json)) {
                        sscan_json(result_json, res)
                    }
                } else {
                    peek(resp.body) $(body_text) {
                        LAST_ERROR = "API returned not OK\n{body_text}"
                    }
                }
            }
        } else {
            peek(resp.body) $(body_text) {
                LAST_ERROR = "FAILED\n{resp.status_code}\n{body_text}\n"
            }
        }
    }
}

def public telegram_getUpdates(updates : get_updates) {
    //! get updates from telegram
    var res : array<update>
    telegram_call("getUpdates", updates, res)
    return <- res
}

def public telegram_sendMessage(msg : send_message) {
    //! send message to telegram chat or user
    var res : message
    telegram_call("sendMessage", msg, res)
    return <- res
}

// Largest byte index <= maxlength at which `text` can be split without cutting a multi-byte
// UTF-8 character — Telegram rejects an invalid-UTF-8 chunk with 400 "strings must be encoded
// in UTF-8". Prefers a newline or space near the limit so chunks break between lines/words.
def private utf8_split_at(text : string; maxlength : int) : int {
    let n = length(text)
    if (n <= maxlength) {
        return n
    }
    var cut = maxlength
    peek_data(text) $(b) {
        while (cut > 0 && (int(b[cut]) & 0xc0) == 0x80) {   // UTF-8 continuation bytes are 0x80..0xBF
            cut--
        }
        var brk = -1
        var p = cut - 1
        let floor = maxlength / 2
        while (p >= floor && brk < 0) {
            let c = int(b[p])
            if (c == 10 || c == 32) {   // '\n' or ' '
                brk = p + 1
            }
            p--
        }
        if (brk > 0) {
            cut = brk
        }
    }
    return cut < 1 ? maxlength : cut
}

def public telegram_sendLongMessage(msg : send_message; maxlength : int = 4096; prefix : string = ""; suffix : string = "") {
    //! send long message to telegram chat or user, splitting at maxlength (never mid-UTF-8-character)
    var res : array<message>
    var text = msg.text
    var cur_msg : send_message
    cur_msg.chat_id = msg.chat_id
    cur_msg.parse_mode = msg.parse_mode
    LAST_ERROR = ""
    while (!empty(text)) {
        if (length(text) > maxlength) {
            let cut = utf8_split_at(text, maxlength)
            cur_msg.text = "{prefix}{text |> slice(0, cut)}{suffix}"
            text = text |> slice(cut)
        } else {
            cur_msg.text = "{prefix}{text}{suffix}"
            text = ""
        }
        res |> emplace <| telegram_sendMessage(cur_msg)
        if (!telegram_get_last_error() |> empty) {
            break
        }
    }
    return <- res
}

def public telegram_getFile(msg : get_file) {
    //! get file information from telegram
    var res : tbotapi::file
    telegram_call("getFile", msg, res)
    return <- res
}

def public telegram_download(f : tbotapi::file) {
    //! download file from telegram
    LAST_ERROR = ""
    let url = "https://api.telegram.org/file/bot{BOT_TOKEN}/{f.file_path}"
    var bytes : array<uint8>
    GET(url) $(resp) {
        if (resp.status_code != http_status.OK) {
            peek(resp.body) $(body_text) {
                LAST_ERROR = "GET failed with status {resp.status_code}\n{body_text}"
            }
            return
        }
        bytes <- get_body_bytes(resp)
    }
    return <- bytes
}

def public telegram_getMe() {
    //! get information about bot
    var res : user
    telegram_call("getMe", get_me(), res)
    return <- res
}

struct public simple_send_photo {
    chat_id : string
    file : string
    reply_to_message_id : int64
    caption : string
    parse_mode : string
}

def public telegram_sendPhoto(photo : simple_send_photo) {
    //! send photo to telegram chat or user
    var settings <- { "photo" => "@{photo.file}", "chat_id" => "{photo.chat_id}" }
    if (photo.reply_to_message_id != 0l) {
        settings |> insert("reply_to_message_id", "{photo.reply_to_message_id}")
    }
    if (!empty(photo.caption)) {
        settings |> insert("caption", "{photo.caption}")
        if (!empty(photo.parse_mode)) {
            settings |> insert("parse_mode", "{photo.parse_mode}")
        }
    }
    LAST_ERROR = ""
    POST("https://api.telegram.org/bot{BOT_TOKEN}/sendPhoto", "", { "Content-Type" => "multipart/form-data" }, settings) $(resp) {
        if (resp.status_code != http_status.OK) {
            peek(resp.body) $(body_text) {
                LAST_ERROR = "HTTPS POST failed with status {resp.status_code}\n{body_text}"
            }
        }
    }
}

def public telegram_setMyCommands(commands : set_my_commands) {
    let res : bool
    telegram_call("setMyCommands", commands, res)
    return res
}

/*
Underscore (_)  Asterisk (*)    Backtick (`)    Left square bracket ([)
Right square bracket (])    Left parenthesis (()    Right parenthesis ())
Tilde (~)   Greater than sign (>)   Hash (#)    Plus sign (+)   Minus sign (-)
Equals sign (=) Vertical bar (|)    Left curly brace ({)    Right curly brace (})
Period (.)  Exclamation mark (!)
*/
def public telegram_escapeMarkdownV2(text : string) {
    return build_string() $(writer) {
        for (Ch in text) {
            if (Ch == '_' || Ch == '*' || Ch == '`' || Ch == '[' || Ch == ']' || Ch == '(' || Ch == ')' || Ch == '~' || Ch == '>' || Ch == '#' || Ch == '+' || Ch == '-' || Ch == '=' || Ch == '|' || Ch == '{' || Ch == '}' || Ch == '.' || Ch == '!') {
                writer |> write_char('\\')
            }
            writer |> write_char(Ch)
        }
    }
}
