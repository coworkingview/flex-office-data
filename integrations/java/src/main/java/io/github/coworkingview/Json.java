package io.github.coworkingview;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * A JSON reader for API responses. Object key order is preserved. Number tokens are
 * kept as the API wrote them, so {@code 214} is not turned into {@code 214.0}.
 */
final class Json {
    private Json() {}

    static Value parse(String text) {
        if (text == null) {
            throw new JsonException("body is null");
        }
        Reader reader = new Reader(text);
        reader.skip();
        Value value = reader.parseValue();
        reader.skip();
        if (!reader.eof()) {
            throw reader.error("trailing data");
        }
        return value;
    }

    static final class JsonException extends IllegalArgumentException {
        JsonException(String message) {
            super(message);
        }
    }

    static final class Value {
        enum Kind {
            OBJECT,
            ARRAY,
            STRING,
            NUMBER,
            BOOLEAN,
            NULL
        }

        static final Value NULL = new Value(Kind.NULL, null, null, null, false);

        private final Kind kind;
        private final Map<String, Value> object;
        private final List<Value> array;
        private final String text;
        private final boolean bool;

        private Value(Kind kind, Map<String, Value> object, List<Value> array, String text, boolean bool) {
            this.kind = kind;
            this.object = object;
            this.array = array;
            this.text = text;
            this.bool = bool;
        }

        static Value object(Map<String, Value> map) {
            return new Value(Kind.OBJECT, Collections.unmodifiableMap(map), null, null, false);
        }

        static Value array(List<Value> list) {
            return new Value(Kind.ARRAY, null, Collections.unmodifiableList(list), null, false);
        }

        static Value string(String text) {
            return new Value(Kind.STRING, null, null, text, false);
        }

        static Value number(String raw) {
            return new Value(Kind.NUMBER, null, null, raw, false);
        }

        static Value bool(boolean value) {
            return new Value(Kind.BOOLEAN, null, null, null, value);
        }

        boolean isNull() {
            return kind == Kind.NULL;
        }

        boolean isObject() {
            return kind == Kind.OBJECT;
        }

        boolean isArray() {
            return kind == Kind.ARRAY;
        }

        boolean isString() {
            return kind == Kind.STRING;
        }

        boolean isNumber() {
            return kind == Kind.NUMBER;
        }

        boolean isBoolean() {
            return kind == Kind.BOOLEAN;
        }

        Map<String, Value> fields() {
            if (!isObject()) {
                throw new JsonException("not an object");
            }
            return object;
        }

        List<Value> elements() {
            if (!isArray()) {
                throw new JsonException("not an array");
            }
            return array;
        }

        String string() {
            if (!isString()) {
                throw new JsonException("not a string");
            }
            return text;
        }

        String rawNumber() {
            if (!isNumber()) {
                throw new JsonException("not a number");
            }
            return text;
        }

        boolean bool() {
            if (!isBoolean()) {
                throw new JsonException("not a boolean");
            }
            return bool;
        }

        /**
         * @return the value, a {@link #NULL} value when the JSON value is null, or
         *     {@code null} when the key is absent or this value is not an object
         */
        Value get(String key) {
            if (!isObject()) {
                return null;
            }
            return object.get(key);
        }

        boolean has(String key) {
            return isObject() && object.containsKey(key);
        }

        String optString(String key) {
            Value value = get(key);
            if (value == null || !value.isString()) {
                return null;
            }
            return value.text;
        }

        /** True for a JSON number whose token has no fraction and no exponent. */
        boolean integral() {
            if (!isNumber()) {
                return false;
            }
            for (int i = 0; i < text.length(); i++) {
                char c = text.charAt(i);
                if (c == '.' || c == 'e' || c == 'E') {
                    return false;
                }
            }
            return true;
        }
    }

    private static final class Reader {
        private final String s;
        private final int n;
        private int i;
        private int depth;

        Reader(String text) {
            this.s = text;
            this.n = text.length();
            if (n > 0 && text.charAt(0) == '\uFEFF') {
                i = 1;
            }
        }

        boolean eof() {
            return i >= n;
        }

        JsonException error(String message) {
            return new JsonException(message + " at index " + i);
        }

        void skip() {
            while (i < n) {
                char c = s.charAt(i);
                if (c == ' ' || c == '\n' || c == '\r' || c == '\t') {
                    i++;
                } else {
                    break;
                }
            }
        }

        Value parseValue() {
            if (i >= n) {
                throw error("unexpected end");
            }
            char c = s.charAt(i);
            if (c == '{') {
                return parseObject();
            }
            if (c == '[') {
                return parseArray();
            }
            if (c == '"') {
                return Value.string(parseString());
            }
            if (c == 't') {
                return literal("true", Value.bool(true));
            }
            if (c == 'f') {
                return literal("false", Value.bool(false));
            }
            if (c == 'n') {
                return literal("null", Value.NULL);
            }
            if (c == '-' || (c >= '0' && c <= '9')) {
                return parseNumber();
            }
            throw error("unexpected character");
        }

        Value literal(String word, Value value) {
            if (s.startsWith(word, i)) {
                i += word.length();
                return value;
            }
            throw error("invalid literal");
        }

        Value parseObject() {
            if (++depth > 64) {
                throw error("nesting too deep");
            }
            expect('{');
            Map<String, Value> map = new LinkedHashMap<String, Value>();
            skip();
            if (peek('}')) {
                i++;
                depth--;
                return Value.object(map);
            }
            while (true) {
                skip();
                if (i >= n || s.charAt(i) != '"') {
                    throw error("expected object key");
                }
                String key = parseString();
                skip();
                expect(':');
                skip();
                map.put(key, parseValue());
                skip();
                if (peek('}')) {
                    i++;
                    depth--;
                    return Value.object(map);
                }
                expect(',');
            }
        }

        Value parseArray() {
            if (++depth > 64) {
                throw error("nesting too deep");
            }
            expect('[');
            List<Value> list = new ArrayList<Value>();
            skip();
            if (peek(']')) {
                i++;
                depth--;
                return Value.array(list);
            }
            while (true) {
                skip();
                list.add(parseValue());
                skip();
                if (peek(']')) {
                    i++;
                    depth--;
                    return Value.array(list);
                }
                expect(',');
            }
        }

        String parseString() {
            expect('"');
            StringBuilder sb = new StringBuilder();
            while (i < n) {
                char c = s.charAt(i++);
                if (c == '"') {
                    return sb.toString();
                }
                if (c == '\\') {
                    if (i >= n) {
                        throw error("bad escape");
                    }
                    char escaped = s.charAt(i++);
                    switch (escaped) {
                        case '"':
                        case '\\':
                        case '/':
                            sb.append(escaped);
                            break;
                        case 'b':
                            sb.append('\b');
                            break;
                        case 'f':
                            sb.append('\f');
                            break;
                        case 'n':
                            sb.append('\n');
                            break;
                        case 'r':
                            sb.append('\r');
                            break;
                        case 't':
                            sb.append('\t');
                            break;
                        case 'u':
                            if (i + 4 > n) {
                                throw error("bad unicode escape");
                            }
                            int codePoint = 0;
                            for (int k = 0; k < 4; k++) {
                                int hex = hex(s.charAt(i++));
                                if (hex < 0) {
                                    throw error("bad unicode escape");
                                }
                                codePoint = (codePoint << 4) | hex;
                            }
                            sb.append((char) codePoint);
                            break;
                        default:
                            throw error("bad escape");
                    }
                } else if (c < 0x20) {
                    throw error("unescaped control character");
                } else {
                    sb.append(c);
                }
            }
            throw error("unterminated string");
        }

        Value parseNumber() {
            int start = i;
            if (peek('-')) {
                i++;
            }
            if (i >= n) {
                throw error("bad number");
            }
            char c = s.charAt(i);
            if (c == '0') {
                i++;
            } else if (c >= '1' && c <= '9') {
                while (i < n && s.charAt(i) >= '0' && s.charAt(i) <= '9') {
                    i++;
                }
            } else {
                throw error("bad number");
            }
            if (i < n && s.charAt(i) == '.') {
                i++;
                int fraction = i;
                while (i < n && s.charAt(i) >= '0' && s.charAt(i) <= '9') {
                    i++;
                }
                if (i == fraction) {
                    throw error("bad number");
                }
            }
            if (i < n && (s.charAt(i) == 'e' || s.charAt(i) == 'E')) {
                i++;
                if (i < n && (s.charAt(i) == '+' || s.charAt(i) == '-')) {
                    i++;
                }
                int exponent = i;
                while (i < n && s.charAt(i) >= '0' && s.charAt(i) <= '9') {
                    i++;
                }
                if (i == exponent) {
                    throw error("bad number");
                }
            }
            return Value.number(s.substring(start, i));
        }

        void expect(char c) {
            if (i >= n || s.charAt(i) != c) {
                throw error("expected '" + c + "'");
            }
            i++;
        }

        boolean peek(char c) {
            return i < n && s.charAt(i) == c;
        }

        static int hex(char c) {
            if (c >= '0' && c <= '9') {
                return c - '0';
            }
            if (c >= 'a' && c <= 'f') {
                return c - 'a' + 10;
            }
            if (c >= 'A' && c <= 'F') {
                return c - 'A' + 10;
            }
            return -1;
        }
    }
}
