import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const webViewApp = path.join(repoRoot, "WebViewApp");
const typesPath = path.join(webViewApp, "src", "types.ts");
const bridgePath = path.join(webViewApp, "src", "bridge.ts");
const uiUtilPath = path.join(repoRoot, "Main", "UIUtil.ahk");

const requireFromWebView = createRequire(path.join(webViewApp, "package.json"));
let ts;
try {
  ts = requireFromWebView("typescript");
} catch (error) {
  throw new Error("Unable to load TypeScript from WebViewApp/node_modules. Run npm.cmd install in WebViewApp first.", {
    cause: error
  });
}

const typesSource = fs.readFileSync(typesPath, "utf8");
const bridgeSource = fs.readFileSync(bridgePath, "utf8");
const uiUtilSource = fs.readFileSync(uiUtilPath, "utf8");
const typesFile = ts.createSourceFile(typesPath, typesSource, ts.ScriptTarget.Latest, true);
const bridgeFile = ts.createSourceFile(bridgePath, bridgeSource, ts.ScriptTarget.Latest, true);

const errors = [];

const interfaceToAhkBuilder = {
  RmtState: { functionName: "RmtBuildState", variableName: "state" },
  RmtSettings: { functionName: "RmtBuildSettings", variableName: "settings" },
  RmtToolState: { functionName: "RmtBuildTools", variableName: "tools" },
  RmtTab: { functionName: "RmtBuildTabs", variableName: "tab" },
  RmtTable: { functionName: "RmtBuildTable", variableName: "table" },
  RmtFold: { functionName: "RmtBuildFolds", variableName: "fold" },
  RmtItem: { functionName: "RmtBuildItem", variableName: "item" }
};

const interfaceToFallbackPath = {
  RmtState: [],
  RmtSettings: ["settings"],
  RmtToolState: ["tools"],
  RmtTab: ["tabs", "[0]"],
  RmtTable: ["tabs", "[0]", "table"],
  RmtFold: ["tabs", "[0]", "table", "folds", "[0]"],
  RmtItem: ["tabs", "[0]", "table", "folds", "[0]", "items", "[0]"]
};

function sortedUnique(values) {
  return [...new Set(values)].sort((a, b) => a.localeCompare(b));
}

function formatList(values) {
  return values.length > 0 ? values.join(", ") : "(none)";
}

function compareSets(label, expected, actual) {
  const expectedSet = new Set(expected);
  const actualSet = new Set(actual);
  const missing = expected.filter((value) => !actualSet.has(value));
  const extra = actual.filter((value) => !expectedSet.has(value));

  if (missing.length > 0 || extra.length > 0) {
    errors.push(`${label}\n  Missing: ${formatList(missing)}\n  Extra: ${formatList(extra)}`);
  }
}

function findInterface(name) {
  for (const statement of typesFile.statements) {
    if (ts.isInterfaceDeclaration(statement) && statement.name.text === name) {
      return statement;
    }
  }
  throw new Error(`Unable to find interface ${name} in WebViewApp/src/types.ts`);
}

function propertyNameText(nameNode) {
  if (ts.isIdentifier(nameNode) || ts.isStringLiteral(nameNode) || ts.isNumericLiteral(nameNode)) {
    return nameNode.text;
  }
  return undefined;
}

function getInterfaceFields(interfaceName) {
  return sortedUnique(
    findInterface(interfaceName).members
      .filter(ts.isPropertySignature)
      .map((member) => propertyNameText(member.name))
      .filter(Boolean)
  );
}

function findVariableInitializer(sourceFile, variableName) {
  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) {
      continue;
    }
    for (const declaration of statement.declarationList.declarations) {
      if (ts.isIdentifier(declaration.name) && declaration.name.text === variableName) {
        return declaration.initializer;
      }
    }
  }
  throw new Error(`Unable to find ${variableName} in WebViewApp/src/bridge.ts`);
}

function getObjectProperty(objectLiteral, propertyName) {
  for (const property of objectLiteral.properties) {
    if (!ts.isPropertyAssignment(property)) {
      continue;
    }
    if (propertyNameText(property.name) === propertyName) {
      return property.initializer;
    }
  }
  return undefined;
}

function getObjectKeys(objectLiteral) {
  return sortedUnique(
    objectLiteral.properties
      .filter(ts.isPropertyAssignment)
      .map((property) => propertyNameText(property.name))
      .filter(Boolean)
  );
}

function getFallbackNode(root, nodePath) {
  let current = root;
  for (const part of nodePath) {
    if (part === "[0]") {
      if (!ts.isArrayLiteralExpression(current)) {
        throw new Error(`Expected array while reading fallback path ${nodePath.join(".")}`);
      }
      current = current.elements.find(ts.isObjectLiteralExpression);
      if (!current) {
        throw new Error(`Missing object element while reading fallback path ${nodePath.join(".")}`);
      }
      continue;
    }

    if (!ts.isObjectLiteralExpression(current)) {
      throw new Error(`Expected object while reading fallback path ${nodePath.join(".")}`);
    }
    current = getObjectProperty(current, part);
    if (!current) {
      throw new Error(`Missing fallback property '${part}' in path ${nodePath.join(".")}`);
    }
  }

  if (!ts.isObjectLiteralExpression(current)) {
    throw new Error(`Fallback path ${nodePath.join(".") || "(root)"} does not resolve to an object.`);
  }
  return current;
}

function extractAhkFunctionBody(functionName) {
  const definitionPattern = new RegExp(`(^|\\r?\\n)${functionName}\\s*\\([^)]*\\)\\s*\\{`, "m");
  const match = definitionPattern.exec(uiUtilSource);
  if (!match) {
    throw new Error(`Unable to find ${functionName}() in Main/UIUtil.ahk`);
  }

  let index = match.index + match[0].lastIndexOf("{");
  let depth = 0;
  for (; index < uiUtilSource.length; index += 1) {
    const char = uiUtilSource[index];
    if (char === "{") {
      depth += 1;
    } else if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return uiUtilSource.slice(match.index, index + 1);
      }
    }
  }

  throw new Error(`Unable to read ${functionName}() body in Main/UIUtil.ahk`);
}

function extractAhkMapKeys(functionName, variableName) {
  const body = extractAhkFunctionBody(functionName);
  const pattern = new RegExp(`${variableName}\\["([^"]+)"\\]\\s*:=`, "g");
  const keys = [];
  let match;
  while ((match = pattern.exec(body))) {
    keys.push(match[1]);
  }
  return sortedUnique(keys);
}

function extractActionTypes() {
  const actionPattern = /\|\s*\{\s*type:\s*"([^"]+)"/g;
  const actions = [];
  let match;
  while ((match = actionPattern.exec(typesSource))) {
    actions.push(match[1]);
  }
  return sortedUnique(actions);
}

function extractDispatchCases() {
  const body = extractAhkFunctionBody("RmtDispatchWebAction");
  const casePattern = /case\s+"([^"]+)":/g;
  const cases = [];
  let match;
  while ((match = casePattern.exec(body))) {
    cases.push(match[1]);
  }
  return sortedUnique(cases);
}

const fallbackRoot = findVariableInitializer(bridgeFile, "fallbackState");
if (!fallbackRoot || !ts.isObjectLiteralExpression(fallbackRoot)) {
  throw new Error("fallbackState must be an object literal in WebViewApp/src/bridge.ts");
}

for (const [interfaceName, builder] of Object.entries(interfaceToAhkBuilder)) {
  const interfaceFields = getInterfaceFields(interfaceName);
  const ahkFields = extractAhkMapKeys(builder.functionName, builder.variableName);
  compareSets(`${interfaceName} vs ${builder.functionName}()`, interfaceFields, ahkFields);

  const fallbackNode = getFallbackNode(fallbackRoot, interfaceToFallbackPath[interfaceName]);
  const fallbackFields = getObjectKeys(fallbackNode);
  compareSets(`${interfaceName} vs fallbackState.${interfaceToFallbackPath[interfaceName].join(".") || "(root)"}`, interfaceFields, fallbackFields);
}

compareSets("RmtAction vs RmtDispatchWebAction()", extractActionTypes(), extractDispatchCases());

if (errors.length > 0) {
  console.error("WebView bridge contract check failed:");
  for (const error of errors) {
    console.error("");
    console.error(error);
  }
  process.exit(1);
}

console.log("WebView bridge contract matches types.ts, bridge.ts, and Main/UIUtil.ahk.");
