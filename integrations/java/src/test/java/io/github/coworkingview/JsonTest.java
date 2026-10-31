package io.github.coworkingview;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.coworkingview.Json.Value;
import java.util.ArrayList;
import java.util.Map;
import org.junit.jupiter.api.Test;

class JsonTest {
    @Test
    void readsObjectsArraysAndScalars() {
        Value value = Json.parse("{\"a\":1,\"b\":\"x\",\"c\":true,\"d\":null,\"e\":[false,2.5]}");
        assertEquals("1", value.get("a").rawNumber());
        assertTrue(value.get("a").integral());
        assertEquals("x", value.optString("b"));
        assertTrue(value.get("c").bool());
        assertTrue(value.get("d").isNull());
        assertNull(value.get("missing"));
        assertFalse(value.get("e").elements().get(0).bool());
        assertEquals("2.5", value.get("e").elements().get(1).rawNumber());
        assertFalse(value.get("e").elements().get(1).integral());
    }

    @Test
    void preservesKeyOrderAndLastDuplicate() {
        Value value = Json.parse("{\"b\":1,\"a\":2,\"b\":3}");
        assertEquals(new ArrayList<String>(value.fields().keySet()).toString(), "[b, a]");
        assertEquals("3", value.get("b").rawNumber());
    }

    @Test
    void unescapesStrings() {
        Value value = Json.parse("\"a\\\"b\\\\c\\n\\u00e4\"");
        assertEquals("a\"b\\c\nä", value.string());
    }

    @Test
    void rejectsTrailingDataAndBrokenNumbers() {
        assertThrows(Json.JsonException.class, () -> Json.parse("1 2"));
        assertThrows(Json.JsonException.class, () -> Json.parse("01"));
        assertThrows(Json.JsonException.class, () -> Json.parse("{\"a\":}"));
        assertThrows(Json.JsonException.class, () -> Json.parse("[1,]"));
    }

    @Test
    void mapIterationIsInsertionOrder() {
        Map<String, Value> fields = Json.parse("{\"dayPass\":1,\"meetingRoom\":2}").fields();
        assertEquals("dayPass", fields.keySet().iterator().next());
    }
}
