pragma Singleton

import QtQuick

QtObject {
    id: root

    property var vars: ({})
    property real last: 0
    property bool hasLast: false

    readonly property var constants: ({ pi: Math.PI, e: Math.E })
    readonly property var funcs: ({
            sqrt: { n: 1, f: a => Math.sqrt(a[0]) },
            cbrt: { n: 1, f: a => Math.cbrt(a[0]) },
            sq: { n: 1, f: a => a[0] * a[0] },
            abs: { n: 1, f: a => Math.abs(a[0]) },
            round: { n: 1, f: a => Math.round(a[0]) },
            floor: { n: 1, f: a => Math.floor(a[0]) },
            ceil: { n: 1, f: a => Math.ceil(a[0]) },
            sin: { n: 1, f: a => Math.sin(a[0]) },
            cos: { n: 1, f: a => Math.cos(a[0]) },
            tan: { n: 1, f: a => Math.tan(a[0]) },
            asin: { n: 1, f: a => Math.asin(a[0]) },
            acos: { n: 1, f: a => Math.acos(a[0]) },
            atan: { n: 1, f: a => Math.atan(a[0]) },
            ln: { n: 1, f: a => Math.log(a[0]) },
            log: { n: 1, f: a => Math.log10(a[0]) },
            exp: { n: 1, f: a => Math.exp(a[0]) },
            pow: { n: 2, f: a => Math.pow(a[0], a[1]) },
            min: { n: 2, f: a => Math.min(a[0], a[1]) },
            max: { n: 2, f: a => Math.max(a[0], a[1]) }
        })

    function reserved(name) {
        return name === "ans" || name in constants || name in funcs;
    }

    function tokenize(src) {
        const out = [];
        let i = 0;
        while (i < src.length) {
            const ch = src[i];
            if (/\s/.test(ch)) {
                i++;
                continue;
            }
            const rest = src.substring(i);
            let m = /^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/i.exec(rest);
            if (m) {
                out.push({ t: "num", v: parseFloat(m[0]) });
                i += m[0].length;
                continue;
            }
            m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(rest);
            if (m) {
                out.push({ t: "id", v: m[0] });
                i += m[0].length;
                continue;
            }
            if (rest.startsWith("**")) {
                out.push({ t: "op", v: "^" });
                i += 2;
                continue;
            }
            if ("+-*/^%(),=".indexOf(ch) >= 0) {
                out.push({ t: "op", v: ch });
                i++;
                continue;
            }
            if (ch === "\u00b2") {
                out.push({ t: "op", v: "\u00b2" });
                i++;
                continue;
            }
            if (ch === "\u221a") {
                out.push({ t: "id", v: "sqrt" });
                i++;
                continue;
            }
            if (ch === "\u00d7") {
                out.push({ t: "op", v: "*" });
                i++;
                continue;
            }
            if (ch === "\u00f7") {
                out.push({ t: "op", v: "/" });
                i++;
                continue;
            }
            throw { msg: "Unexpected \"" + ch + "\"", incomplete: false };
        }
        return out;
    }

    function run(tokens, scope) {
        let pos = 0;
        const fail = (msg, incomplete) => {
            throw { msg: msg, incomplete: incomplete === true };
        };
        const peek = () => tokens[pos];
        const isOp = v => pos < tokens.length && tokens[pos].t === "op" && tokens[pos].v === v;
        const expect = v => {
            if (!isOp(v))
                fail(pos >= tokens.length ? "Incomplete expression" : "Expected \"" + v + "\"", pos >= tokens.length);
            pos++;
        };

        const expr = () => {
            let v = term();
            while (isOp("+") || isOp("-")) {
                const op = tokens[pos++].v;
                const r = term();
                v = op === "+" ? v + r : v - r;
            }
            return v;
        };

        const term = () => {
            let v = unary();
            while (isOp("*") || isOp("/") || isOp("%")) {
                const op = tokens[pos++].v;
                const r = unary();
                if (op === "*")
                    v = v * r;
                else if (op === "/")
                    v = v / r;
                else
                    v = v % r;
            }
            return v;
        };

        const unary = () => {
            if (isOp("-")) {
                pos++;
                return -unary();
            }
            if (isOp("+")) {
                pos++;
                return unary();
            }
            return power();
        };

        const power = () => {
            let base = postfix();
            if (isOp("^")) {
                pos++;
                return Math.pow(base, unary());
            }
            return base;
        };

        const postfix = () => {
            let v = primary();
            while (isOp("\u00b2")) {
                pos++;
                v = v * v;
            }
            return v;
        };

        const primary = () => {
            const tok = peek();
            if (!tok)
                fail("Incomplete expression", true);
            if (tok.t === "num") {
                pos++;
                return tok.v;
            }
            if (tok.t === "id") {
                pos++;
                const name = tok.v;
                if (name in funcs && (isOp("(") || !(name in scope))) {
                    const fn = funcs[name];
                    let args;
                    if (isOp("(")) {
                        pos++;
                        args = [];
                        if (!isOp(")")) {
                            args.push(expr());
                            while (isOp(",")) {
                                pos++;
                                args.push(expr());
                            }
                        }
                        expect(")");
                    } else {
                        args = [power()];
                    }
                    if (args.length !== fn.n)
                        fail(name + " takes " + fn.n + " argument" + (fn.n > 1 ? "s" : ""), false);
                    return fn.f(args);
                }
                if (name in scope)
                    return scope[name];
                fail("Unknown variable \"" + name + "\"", false);
            }
            if (isOp("(")) {
                pos++;
                const v = expr();
                expect(")");
                return v;
            }
            fail("Unexpected \"" + tok.v + "\"", false);
        };

        const v = expr();
        if (pos < tokens.length)
            fail("Unexpected \"" + tokens[pos].v + "\"", false);
        return v;
    }

    function format(v) {
        if (Number.isInteger(v) && Math.abs(v) < 1e15)
            return String(v);
        return String(parseFloat(v.toPrecision(12)));
    }

    function evaluate(text) {
        const src = text.trim();
        if (src.length === 0)
            return { ok: false, empty: true };
        try {
            const tokens = tokenize(src);
            let name = "";
            let body = tokens;
            if (tokens.length >= 2 && tokens[0].t === "id" && tokens[1].t === "op" && tokens[1].v === "=") {
                name = tokens[0].v;
                if (reserved(name))
                    return { ok: false, msg: "\"" + name + "\" is reserved", incomplete: false };
                body = tokens.slice(2);
            }
            const scope = Object.assign({}, constants, vars);
            if (hasLast)
                scope.ans = last;
            const v = run(body, scope);
            if (typeof v !== "number" || !isFinite(v))
                return { ok: false, msg: "Result is not a finite number", incomplete: false };
            return { ok: true, value: v, text: format(v), name: name };
        } catch (err) {
            if (err && err.msg !== undefined)
                return { ok: false, msg: err.msg, incomplete: err.incomplete === true };
            return { ok: false, msg: "Invalid expression", incomplete: false };
        }
    }

    function commit(result): void {
        last = result.value;
        hasLast = true;
        if (result.name.length > 0) {
            const next = Object.assign({}, vars);
            next[result.name] = result.value;
            vars = next;
        }
    }

    function remove(name): void {
        const next = Object.assign({}, vars);
        delete next[name];
        vars = next;
    }

    function list() {
        return Object.keys(vars).sort().map(k => ({ name: k, value: vars[k], text: format(vars[k]) }));
    }
}
