import test from "node:test";
import assert from "node:assert/strict";
import { contextualScreen, issueDraft } from "../src/models.js";

const clean = { decision: "pass", reasons: [] };
const image = { bodyBase64: "AA==" };
const draft = {
  title: "Button label is cut off",
  category: "bug",
  reported: "The label is cut off. Saving still works.",
  requested: "Show the complete label.",
  steps: ["unknown"],
  severity: "sev-bug",
  captureReferences: ["capture-1.jpg"],
};

test("structured vision preserves hold reasons and uses only embedded image data", async () => {
  for (const reasons of [
    [],
    ["private_record"],
    ["credential"],
    ["prohibited_content"],
    ["prompt_injection"],
    ["uncertain"],
  ]) {
    let calls = 0;
    const env = {
      AI: {
        run: async (model, input) => {
          calls++;
          if (calls === 1) return { response: clean };
          assert.equal(model, "@cf/meta/llama-4-scout-17b-16e-instruct");
          assert.equal(input.response_format.type, "json_schema");
          assert.equal(
            input.response_format.json_schema.additionalProperties,
            false,
          );
          const content = input.messages[1].content;
          assert.equal(content.length, 2);
          assert.equal(content[1].image_url.url, "data:image/jpeg;base64,AA==");
          assert.equal(input.tools, undefined);
          return {
            response: { decision: reasons.length ? "hold" : "pass", reasons },
          };
        },
      },
    };
    assert.deepEqual(
      await contextualScreen(env, "The label is clipped.", [image]),
      reasons,
    );
    assert.equal(calls, 2);
  }
});

test("vision prose, fences, inconsistent verdicts, and unknown findings fail closed", async () => {
  for (const response of [
    "**Decision:** pass\n\n**Reasons:** []",
    '```json\n{"decision":"pass","reasons":[]}\n```',
    "PASS",
    { decision: "pass", reasons: ["credential"] },
    { decision: "hold", reasons: ["unknown_code"] },
  ]) {
    let calls = 0;
    const env = {
      AI: { run: async () => ({ response: ++calls === 1 ? clean : response }) },
    };
    await assert.rejects(
      contextualScreen(env, "The label is clipped.", [image]),
      { message: "model_invalid" },
    );
  }
});

test("text requests documented JSON mode and still rejects inconsistent verdicts", async () => {
  const env = {
    AI: {
      run: async (model, input) => {
        assert.equal(model, "@cf/meta/llama-3.3-70b-instruct-fp8-fast");
        assert.equal(input.response_format.type, "json_schema");
        assert.equal(
          input.response_format.json_schema.additionalProperties,
          false,
        );
        assert.equal(
          input.response_format.json_schema.properties.reasons.uniqueItems,
          undefined,
        );
        assert.equal(input.tools, undefined);
        return { response: { decision: "pass", reasons: ["uncertain"] } };
      },
    },
  };
  await assert.rejects(contextualScreen(env, "The label is clipped."), {
    message: "model_invalid",
  });
});

test("draft JSON schema restricts capture references and leaves facts for owner review", async () => {
  const env = {
    AI: {
      run: async (model, input) => {
        assert.equal(model, "@cf/meta/llama-3.3-70b-instruct-fp8-fast");
        assert.equal(input.response_format.type, "json_schema");
        const schema = input.response_format.json_schema;
        assert.equal(schema.additionalProperties, false);
        assert.deepEqual(schema.properties.captureReferences.items.enum, [
          "capture-1.jpg",
        ]);
        assert.equal(input.tools, undefined);
        return { response: draft };
      },
    },
  };
  assert.deepEqual(
    await issueDraft(env, "The label is cut off. Saving still works.", [
      "capture-1.jpg",
    ]),
    draft,
  );
});

test("model tool calls and fenced draft output never receive authority", async () => {
  const toolEnv = {
    AI: {
      run: async () => ({ response: clean, tool_calls: [{ name: "publish" }] }),
    },
  };
  await assert.rejects(contextualScreen(toolEnv, "A label is clipped."), {
    message: "model_invalid",
  });
  const fencedEnv = {
    AI: {
      run: async () => ({
        response: "```json\n" + JSON.stringify(draft) + "\n```",
      }),
    },
  };
  await assert.rejects(
    issueDraft(fencedEnv, "A label is clipped.", ["capture-1.jpg"]),
    { message: "model_invalid" },
  );
});

test("contextual screening covers escaped Unicode and the final text without an oversized model request", async () => {
  const text = Array.from({ length: 3500 }, (_, n) => `${n}:雪🦊\u0001\n`).join("") + "TAIL-INJECTION-MARKER";
  const chunks = [];
  let reservations = 0;
  const env = { AI: { run: async (_model, input) => {
    const serialized = input.messages[1].content;
    assert.ok(new TextEncoder().encode(serialized).length <= 8040);
    const chunk = JSON.parse(serialized).submittedData;
    assert.ok(chunk.length > 0);
    chunks.push(chunk);
    return { response: chunk.includes("TAIL-INJECTION-MARKER")
      ? { decision: "hold", reasons: ["prompt_injection"] } : clean };
  } } };
  const reasons = await contextualScreen(env, text, [], async () => { reservations++; });
  assert.ok(chunks.length > 1);
  assert.equal(reservations, chunks.length);
  let covered = 0;
  for (const chunk of chunks) {
    const start = text.indexOf(chunk, Math.max(0, covered - 1024));
    assert.ok(start >= 0 && start <= covered);
    covered = Math.max(covered, start + chunk.length);
  }
  assert.equal(covered, text.length);
  assert.ok(reasons.includes("prompt_injection"));
});

test("a late contextual chunk failure prevents a successful result", async () => {
  let calls = 0;
  const env = { AI: { run: async () => ({ response: ++calls === 1 ? clean : "not JSON" }) } };
  await assert.rejects(contextualScreen(env, "a".repeat(20000)), { message: "model_invalid" });
  assert.equal(calls, 2);
});

test("drafts exceeding the documented context budget stop before reserving or calling a model", async () => {
  let calls = 0;
  const env = { AI: { run: async () => { calls++; return { response: draft }; } } };
  await assert.rejects(issueDraft(env, "a".repeat(15000), ["capture-1.jpg"], async () => { calls++; }), { message: "draft_context_limit" });
  assert.equal(calls, 0);
});
