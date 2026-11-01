package com.coworkingview.eclipse;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * A small JSON reader for the Price Index payload. The plug-in does not take a
 * JSON library dependency.
 */
public final class Json {

    private Json() {
    }

    public sealed interface Value permits Obj, Arr, Str, Num, Bool, Null {
    }

    public record Obj(Map<String, Value> fields) implements Value {
        public Value get(String key) {
            return fields.get(key);
        }

        public Obj obj(String key) {
            Value value = fields.get(key);
            return value instanceof Obj obj ? obj : null;
        }

        public Arr arr(String key) {
            Value value = fields.get(key);
            return value instanceof Arr arr ? arr : null;
        }

        public String str(String key) {
            Value value = fields.get(key);
            return value instanceof Str str ? str.value() : null;
        }
    }

    public record Arr(List<Value> items) implements Value {
    }

    public record Str(String value) implements Value {
    }

    public record Num(String token) implements Value {
    }

    public record Bool(boolean value) implements Value {
    }

    public record Null() implements Value {
    }

    public static final class JsonException extends IllegalArgumentException {
        private static final long serialVersionUID = 1L;

        public JsonException(String message) {
            super(message);
        }
    }

    public static Value parse(String text) {
        if (text == null || text.isBlank()) {
            throw new JsonException("The response was empty.");
        }
        if (text.length() > 8_000_000) {
            throw new JsonException("The response is too large.");
        }
        Parser parser = new Parser(text);
        Value value = parser.parseValue(0);
        parser.skipWs();
        if (!parser.eof()) {
            throw new JsonException("Unexpected data after the JSON value.");
        }
        return value;
    }

    private static final class Parser {
        private final String source;
        private int index;

        Parser(String source) {
            this.source = source;
        }

        boolean eof() {
            return index >= source.length();
        }

        void skipWs() {
            while (index < source.length()) {
                char character = source.charAt(index);
                if (character == ' ' || character == '\n' || character == '\r' || character == '\t') {
                    index++;
                } else {
                    break;
                }
            }
        }

        Value parseValue(int depth) {
            if (depth > 40) {
                throw new JsonException("The JSON nesting is too deep.");
            }
            skipWs();
            if (eof()) {
                throw new JsonException("The JSON value ended early.");
            }
            char character = source.charAt(index);
            return switch (character) {
                case '{' -> object(depth);
                case '[' -> array(depth);
                case '"' -> new Str(string());
                case 't' -> bool(true);
                case 'f' -> bool(false);
                case 'n' -> nil();
                default -> number();
            };
        }

        private Obj object(int depth) {
            index++;
            Map<String, Value> fields = new LinkedHashMap<>();
            skipWs();
            if (!eof() && source.charAt(index) == '}') {
                index++;
                return new Obj(fields);
            }
            while (true) {
                skipWs();
                if (eof() || source.charAt(index) != '"') {
                    throw new JsonException("Expected an object key.");
                }
                String key = string();
                skipWs();
                if (eof() || source.charAt(index) != ':') {
                    throw new JsonException("Expected a colon after a key.");
                }
                index++;
                fields.put(key, parseValue(depth + 1));
                skipWs();
                if (eof()) {
                    throw new JsonException("The object ended early.");
                }
                char character = source.charAt(index++);
                if (character == '}') {
                    return new Obj(fields);
                }
                if (character != ',') {
                    throw new JsonException("Expected a comma in an object.");
                }
            }
        }

        private Arr array(int depth) {
            index++;
            List<Value> items = new ArrayList<>();
            skipWs();
            if (!eof() && source.charAt(index) == ']') {
                index++;
                return new Arr(items);
            }
            while (true) {
                items.add(parseValue(depth + 1));
                skipWs();
                if (eof()) {
                    throw new JsonException("The array ended early.");
                }
                char character = source.charAt(index++);
                if (character == ']') {
                    return new Arr(items);
                }
                if (character != ',') {
                    throw new JsonException("Expected a comma in an array.");
                }
            }
        }

        private String string() {
            index++;
            StringBuilder builder = new StringBuilder();
            while (!eof()) {
                char character = source.charAt(index++);
                if (character == '"') {
                    return builder.toString();
                }
                if (character == '\\') {
                    if (eof()) {
                        throw new JsonException("The string escape ended early.");
                    }
                    char escaped = source.charAt(index++);
                    switch (escaped) {
                        case '"', '\\', '/' -> builder.append(escaped);
                        case 'b' -> builder.append('\b');
                        case 'f' -> builder.append('\f');
                        case 'n' -> builder.append('\n');
                        case 'r' -> builder.append('\r');
                        case 't' -> builder.append('\t');
                        case 'u' -> {
                            if (index + 4 > source.length()) {
                                throw new JsonException("The unicode escape ended early.");
                            }
                            int codePoint = Integer.parseInt(source.substring(index, index + 4), 16);
                            builder.append((char) codePoint);
                            index += 4;
                        }
                        default -> throw new JsonException("Unknown string escape.");
                    }
                } else if (character < 0x20) {
                    throw new JsonException("A control character was not escaped.");
                } else {
                    builder.append(character);
                    if (builder.length() > 1_000_000) {
                        throw new JsonException("A string is too long.");
                    }
                }
            }
            throw new JsonException("The string ended early.");
        }

        private Num number() {
            int start = index;
            if (source.charAt(index) == '-') {
                index++;
            }
            if (eof() || !digit(source.charAt(index))) {
                throw new JsonException("Expected a number.");
            }
            if (source.charAt(index) == '0') {
                index++;
            } else {
                while (!eof() && digit(source.charAt(index))) {
                    index++;
                }
            }
            if (!eof() && source.charAt(index) == '.') {
                index++;
                if (eof() || !digit(source.charAt(index))) {
                    throw new JsonException("Expected a digit after the decimal point.");
                }
                while (!eof() && digit(source.charAt(index))) {
                    index++;
                }
            }
            if (!eof() && (source.charAt(index) == 'e' || source.charAt(index) == 'E')) {
                index++;
                if (!eof() && (source.charAt(index) == '+' || source.charAt(index) == '-')) {
                    index++;
                }
                if (eof() || !digit(source.charAt(index))) {
                    throw new JsonException("Expected an exponent.");
                }
                while (!eof() && digit(source.charAt(index))) {
                    index++;
                }
            }
            return new Num(source.substring(start, index));
        }

        private Bool bool(boolean value) {
            String word = value ? "true" : "false";
            if (!source.startsWith(word, index)) {
                throw new JsonException("Expected " + word + ".");
            }
            index += word.length();
            return new Bool(value);
        }

        private Null nil() {
            if (!source.startsWith("null", index)) {
                throw new JsonException("Expected null.");
            }
            index += 4;
            return new Null();
        }

        private static boolean digit(char character) {
            return character >= '0' && character <= '9';
        }
    }
}
