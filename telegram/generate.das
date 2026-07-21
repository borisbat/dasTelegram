// Generator for tbotapi.das from Telegram Bot API JSON spec
// Source: https://github.com/PaulSonOfLars/telegram-bot-api-spec/blob/main/api.json
options gen2
options _comment_hygiene = true

require daslib/json_boost
require strings
require daslib/fio

var g_FOUT = fstdout()

// --- Name helpers ---

let RESERVED_NAMES <- { "type" => "_type", "options" => "_options", "label" => "_label", "from" => "_from" }

def sanitize_name(name : string) : string {
    return RESERVED_NAMES?[name] ?? name
}

def to_snake_case(name : string) : string {
    return build_string() $(writer) {
        var prev_upper = false
        for (i, Ch in count(), name) {
            let is_upper = Ch >= 'A' && Ch <= 'Z'
            if (is_upper && i > 0 && !prev_upper) {
                writer |> write("_")
            }
            writer |> write_char(is_upper ? Ch - 'A' + 'a' : Ch)
            prev_upper = is_upper
        }
    }
}

// --- Type mapping ---

def map_type(tname : string; is_optional : bool) : string {
    if (tname == "Integer") {
        return "int64"
    }
    if (tname == "Float" || tname == "Float number") {
        return "float"
    }
    if (tname == "String") {
        return "string"
    }
    if (tname == "Boolean" || tname == "True") {
        return "bool"
    }
    if (tname == "Integer or String") {
        return "string"
    }
    if (tname == "InputFile" || tname == "InputFile or String") {
        return "string"
    }
    if (tname |> starts_with("Array of Array of ")) {
        let inner = tname |> slice(length("Array of Array of "))
        return "array<array<{map_type(inner, false)}>>"
    }
    if (tname |> starts_with("Array of ")) {
        let inner = tname |> slice(length("Array of "))
        return "array<{map_type(inner, false)}>"
    }
    let sname = to_snake_case(tname)
    return is_optional ? "{sname}?" : sname
}

def resolve_field_type(field_jv : JsonValue const?; is_optional : bool) : string {
    var type_names : array<string>
    unsafe {
        let types_jv = field_jv?["types"]
        if (types_jv != null && (types_jv.value is _array)) {
            type_names |> reserve(length(types_jv.value as _array))
            for (t in types_jv.value as _array) {
                type_names |> push(t ?? "")
            }
        }
    }
    if (length(type_names) == 1) {
        return map_type(type_names[0], is_optional)
    }
    // multiple types = union
    var has_string = false
    var has_integer = false
    var struct_type = ""
    for (tname in type_names) {
        if (tname == "String") {
            has_string = true
        } elif (tname == "Integer") {
            has_integer = true
        } elif (tname == "Boolean" || tname == "True" || tname == "Float") {
            pass
        } elif (struct_type |> empty) {
            struct_type = tname
        }
    }
    if (has_integer && has_string) {
        return "string"
    }
    if (!struct_type |> empty) {
        return map_type(struct_type, true)
    }
    return "string"
}

// --- Code generation ---

def process_struct(name : string; type_jv : JsonValue const?) {
    let sname = to_snake_case(name)
    // collect description
    var comment = ""
    unsafe {
        let desc_jv = type_jv?["description"]
        if (desc_jv != null && (desc_jv.value is _array)) {
            for (d in desc_jv.value as _array) {
                if (!comment |> empty) {
                    comment = "{comment} " // nolint:PERF004 code generator building description string
                }
                comment = "{comment}{d ?? ""}" // nolint:PERF004 code generator building description string
            }
        }
    }
    g_FOUT |> fprint("struct {sname} \{\n")
    g_FOUT |> fprint("    //! {comment}\n")
    // check for fields
    let fields_jv = type_jv?["fields"]
    if (fields_jv == null || (fields_jv.value is _null)) {
        g_FOUT |> fprint("    _dummy : bool    //! no fields\n")
    } else {
        unsafe {
            if (fields_jv.value is _array) {
                for (field_jv in fields_jv.value as _array) {
                    let raw_name = field_jv?["name"] ?? ""
                    let fname = sanitize_name(raw_name)
                    let required = field_jv?["required"] ?? false
                    let fdesc = field_jv?["description"] ?? ""
                    let is_optional = !required
                    let ftype = resolve_field_type(field_jv, is_optional)
                    var annotations = ""
                    if (fname != raw_name) {
                        annotations = "@rename "
                    }
                    if (is_optional) {
                        annotations = "{annotations}@optional "
                    }
                    if (!annotations |> empty) {
                        g_FOUT |> fprint("    {annotations}{fname} : {ftype}    //! {fdesc}\n")
                    } else {
                        g_FOUT |> fprint("    {fname} : {ftype}    //! {fdesc}\n")
                    }
                }
            }
        }
    }
    g_FOUT |> fprint("\}\n\n")
}

def process_types(root : JsonValue?) {
    let types_jv = root?["types"]
    if (types_jv == null) {
        panic("no types in api.json")
    }
    unsafe {
        let tobj & = types_jv.value as _object
        for (tname, tvalue in keys(tobj), values(tobj)) {
            process_struct(tname, tvalue)
        }
    }
}

def process_methods(root : JsonValue?) {
    let methods_jv = root?["methods"]
    if (methods_jv == null) {
        return
    }
    unsafe {
        let mobj & = methods_jv.value as _object
        for (mname, mvalue in keys(mobj), values(mobj)) {
            process_struct(mname, mvalue)
        }
    }
}

[export]
def main() {
    let api_text = fread("{get_das_root()}/modules/dasTelegram/telegram/api.json")
    if (api_text |> empty) {
        panic("failed to read api.json")
    }
    var error = ""
    var root = read_json(api_text, error)
    if (root == null) {
        panic("failed to parse api.json: {error}")
    }
    fopen("{get_das_root()}/modules/dasTelegram/telegram/tbotapi.das", "w") $(ff) {
        if (ff == null) {
            panic("failed to open output file")
        }
        g_FOUT = ff
        g_FOUT |> fprint("// This file was generated by dasTelegram/telegram/generate.das\n")
        g_FOUT |> fprint("// Source: https://github.com/PaulSonOfLars/telegram-bot-api-spec\n")
        let version = root?["version"] ?? ""
        let release = root?["release_date"] ?? ""
        g_FOUT |> fprint("// {version}, {release}\n")
        g_FOUT |> fprint("options gen2\n")
        g_FOUT |> fprint("options indenting = 4\n")
        g_FOUT |> fprint("options no_unused_block_arguments = false\n")
        g_FOUT |> fprint("options no_unused_function_arguments = false\n")
        g_FOUT |> fprint("\n")
        g_FOUT |> fprint("module tbotapi shared public\n")
        g_FOUT |> fprint("\n")
        g_FOUT |> fprint("// sscan_json/sprint_json are builtins — no json_boost needed\n")
        g_FOUT |> fprint("\n")
        g_FOUT |> fprint("// ============ TYPES ============\n\n")
        process_types(root)
        g_FOUT |> fprint("// ============ METHODS (request structs) ============\n\n")
        process_methods(root)
    }
    unsafe {
        delete root
    }
    print("generation complete\n")
}
