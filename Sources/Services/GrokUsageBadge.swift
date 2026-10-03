//
//  GrokUsageBadge.swift
//  Grok for Mac
//
//  Adds a compact usage bolt inline to the right of the grok.com sidebar
//  profile name. One click opens Grok's settings Usage tab the same way
//  Payments does: the in-page settings store setTab("usage") + setOpen(true).
//  A full navigation to /?_s=usage is only a fallback. If that dialog exposes
//  a total percentage, it is cached locally as an optional label.
//

import Foundation
import WebKit

enum GrokUsageBadge {
    static let refreshIntervalKey = "grok.usageBadgeRefreshSeconds"
    static let percentStorageKey = "grok.usageBadge.percent"
    static let defaultRefreshSeconds = 120

    /// Persisted optional refresh interval (seconds). Clamped 30…3600.
    static var refreshIntervalSeconds: Int {
        get {
            let raw = UserDefaults.standard.object(forKey: refreshIntervalKey) as? Int
            let value = raw ?? defaultRefreshSeconds
            return min(3600, max(30, value))
        }
        set {
            UserDefaults.standard.set(min(3600, max(30, newValue)), forKey: refreshIntervalKey)
        }
    }

    /// Inject / refresh the bolt on a finished grok.com navigation.
    static func injectIfNeeded(into webView: WKWebView) {
        guard let host = webView.url?.host?.lowercased(),
              host == "grok.com" || host.hasSuffix(".grok.com") else {
            return
        }

        let js = makeInjectorJavaScript(refreshSeconds: refreshIntervalSeconds)
        webView.evaluateJavaScript(js, completionHandler: { _, error in
            #if DEBUG
            if let error {
                print("[UsageBolt] inject error: \(error.localizedDescription)")
            }
            #endif
        })
    }

    /// Kept as a compatibility hook for older settings notifications. Usage is
    /// intentionally owned by grok.com; API-key changes do not alter this UI.
    static func pushAPILabel(_ label: String?, into webView: WKWebView) {
        _ = label
        _ = webView
    }

    // MARK: - JavaScript

    private static func makeInjectorJavaScript(refreshSeconds: Int) -> String {
        return """

        (function() {
          if (window.__grokUsageBoltInstalled) {
            window.__grokUsageBoltRender && window.__grokUsageBoltRender();
            return;
          }
          window.__grokUsageBoltInstalled = true;

          var REFRESH_MS = \(refreshSeconds) * 1000;
          var PERCENT_KEY = "grok.usageBadge.percent";
          var state = { percent: null };

          function readStoredPercent() {
            try {
              var raw = window.localStorage.getItem(PERCENT_KEY);
              var value = parseInt(raw || "", 10);
              return isFinite(value) && value >= 0 && value <= 100 ? value : null;
            } catch (e) { return null; }
          }

          function savePercent(value) {
            if (!isFinite(value) || value < 0 || value > 100) return;
            state.percent = Math.round(value);
            try { window.localStorage.setItem(PERCENT_KEY, String(state.percent)); } catch (e) {}
          }

          state.percent = readStoredPercent();

          function visible(el) {
            if (!el || !el.isConnected) return false;
            var style = window.getComputedStyle(el);
            var rect = el.getBoundingClientRect();
            return style.display !== "none" && style.visibility !== "hidden" &&
              parseFloat(style.opacity || "1") > 0 && rect.width > 0 && rect.height > 0;
          }

          function textOf(el) {
            if (!el) return "";
            var clone = null;
            if (el.querySelector && el.querySelector("#grok-native-usage-bolt")) {
              clone = el.cloneNode(true);
              var bolt = clone.querySelector("#grok-native-usage-bolt");
              if (bolt) bolt.remove();
              el = clone;
            }
            return ((el.innerText || el.textContent || "") + "").replace(/\\s+/g, " ").trim();
          }

          function skipName(text) {
            return /^(new chat|home|history|images|speech|files|apps|settings|upgrade|search|projects|tasks|imagine|voice|build|grok|super.?grok|account|billing|usage|help|sign.?out|log.?out)$/i.test(text);
          }

          function findProfileHost() {
            var best = null;
            var nodes = document.querySelectorAll("button, a, [role='button']");
            for (var i = 0; i < nodes.length; i++) {
              var el = nodes[i];
              if (!visible(el)) continue;
              var rect = el.getBoundingClientRect();
              if (rect.width < 48 || rect.height < 28) continue;
              if (rect.left > 360 || rect.right < 0) continue;
              if (rect.bottom < window.innerHeight - 150 || rect.top > window.innerHeight - 20) continue;
              if (el.id === "grok-native-usage-bolt") continue;
              var source = el.innerText || "";
              if (el.querySelector("#grok-native-usage-bolt")) {
                var clone = el.cloneNode(true);
                var innerBolt = clone.querySelector("#grok-native-usage-bolt");
                if (innerBolt) innerBolt.remove();
                source = clone.innerText || "";
              }
              var lines = source.split("\\n").map(function(x) { return x.replace(/\\s+/g, " ").trim(); }).filter(Boolean);
              if (!lines.length) continue;
                            var name = lines[0];
              name = name.replace(/\\s*ϟ.*$/, "").trim();
              if (name.length < 2 || name.length > 48 || skipName(name)) continue;
              if (/^\\d+%/.test(name) || /usage|api|payments|general/i.test(name)) continue;
              var score = rect.bottom;
              if (el.querySelector("img")) score += 80;
              if (/\\s/.test(name)) score += 40;
              if (!best || score > best.score) best = { el: el, name: name, score: score };
            }
            return best;
          }

          function clickElement(el) {
            if (!el) return false;
            try {
              el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
            } catch (e) {
              try { el.click(); } catch (ignored) {}
            }
            return true;
          }

          function usagePercentFromText(text) {
            if (!text || !/\\busage\\b/i.test(text)) return null;
            var found = [];
            var re = /(\\d{1,3})\\s*%/g;
            var match;
            while ((match = re.exec(text)) !== null) {
              var value = parseInt(match[1], 10);
              if (value < 0 || value > 100) continue;
              var nearby = text.slice(Math.max(0, match.index - 90), Math.min(text.length, match.index + match[0].length + 90));
              var priority = /\\b(total|overall|combined|weekly)\\b/i.test(nearby) ? 4 : (/%\\s*used|\\bused\\b/i.test(nearby) ? 3 : 1);
              found.push({ value: value, priority: priority, index: match.index });
            }
            if (!found.length) return null;
            var unique = [];
            for (var i = 0; i < found.length; i++) {
              if (unique.indexOf(found[i].value) < 0) unique.push(found[i].value);
            }
            if (unique.length >= 3) {
              for (var a = 0; a < unique.length; a++) {
                var rest = 0;
                for (var b = 0; b < unique.length; b++) if (b !== a) rest += unique[b];
                if (Math.abs(rest - unique[a]) <= 2) return unique[a];
              }
            }
            found.sort(function(a, b) { return (b.priority - a.priority) || (a.index - b.index); });
            return found[0].value;
          }

          function capturePercentFromOpenUsageDialog() {
            var nodes = document.querySelectorAll("[role='dialog'], [aria-modal='true'], [data-state='open']");
            for (var i = 0; i < nodes.length; i++) {
              if (!visible(nodes[i])) continue;
              var value = usagePercentFromText(textOf(nodes[i]));
              if (value != null) { savePercent(value); window.__grokUsageBoltRender(); return; }
            }
          }

          function scheduleCapture() {
            [400, 900, 1600, 2800].forEach(function(delay) {
              setTimeout(capturePercentFromOpenUsageDialog, delay);
            });
          }

          function fnSource(fn) {
            try { return Function.prototype.toString.call(fn); } catch (e) { return ""; }
          }

          function snapshotFromHook(hook) {
            var queue = hook && hook.queue;
            if (queue && typeof queue.getSnapshot === "function") {
              try { return queue.getSnapshot(); } catch (e) { return null; }
            }
            if (hook && hook.memoizedState && typeof hook.memoizedState.getSnapshot === "function") {
              try { return hook.memoizedState.getSnapshot(); } catch (e2) { return null; }
            }
            return null;
          }

          function findSettingsActions() {
            var setTab = null;
            var setOpen = null;
            var fiberKey = null;
            var seed = document.querySelector("#__next") || document.body;
            var nodes = [seed].concat(Array.prototype.slice.call(document.querySelectorAll("button, div")));
            for (var i = 0; i < nodes.length && !fiberKey; i++) {
              var el = nodes[i];
              if (!el) continue;
              var keys = Object.keys(el);
              for (var k = 0; k < keys.length; k++) {
                if (keys[k].indexOf("__reactFiber$") === 0 || keys[k].indexOf("__reactInternalInstance$") === 0) {
                  fiberKey = keys[k];
                  seed = el;
                  break;
                }
              }
            }
            if (!fiberKey || !seed[fiberKey]) return { setTab: null, setOpen: null };
            var root = seed[fiberKey];
            var up = 0;
            while (root.return && up++ < 80) root = root.return;
            var stack = [root];
            var seen = 0;
            while (stack.length && seen++ < 8000 && (!setTab || !setOpen)) {
              var fiber = stack.pop();
              if (!fiber) continue;
              if (fiber.child) stack.push(fiber.child);
              if (fiber.sibling) stack.push(fiber.sibling);
              var hook = fiber.memoizedState;
              var hops = 0;
              while (hook && hops++ < 60 && (!setTab || !setOpen)) {
                var snap = snapshotFromHook(hook);
                if (typeof snap === "function") {
                  var src = fnSource(snap);
                  if (!setTab && src.indexOf("{tab:") !== -1 && src.indexOf("#e") !== -1) setTab = snap;
                  else if (!setOpen && src.indexOf("open:") !== -1 && src.indexOf("{tab:") === -1 && src.indexOf("#e") !== -1) setOpen = snap;
                }
                hook = hook.next;
              }
            }
            return { setTab: setTab, setOpen: setOpen };
          }

          function clickUsageNav() {
            var buttons = document.querySelectorAll("[data-settings-nav-button]");
            for (var i = 0; i < buttons.length; i++) {
              var label = textOf(buttons[i]).toLowerCase();
              if (label !== "usage") continue;
              var selected = buttons[i].getAttribute("data-settings-nav-selected");
              if (selected == null) clickElement(buttons[i]);
              return true;
            }
            return false;
          }

          function usageDetailIsOpen() {
            var nodes = document.querySelectorAll("[role='dialog'], [aria-modal='true']");
            for (var i = 0; i < nodes.length; i++) {
              if (!visible(nodes[i])) continue;
              var text = textOf(nodes[i]);
              if (/\\busage\\b/i.test(text) && /%\\s*used|\\bweekly\\b|\\bextra usage credits\\b/i.test(text)) return true;
            }
            return false;
          }

          function assignUsageDeepLink() {
            try {
              var target = new URL(window.location.href);
              if (target.searchParams.get("_s") === "usage") return false;
              target.hash = "";
              target.searchParams.set("_s", "usage");
              window.location.assign(target.toString());
              return true;
            } catch (e) { return false; }
          }

          function openUsageDetails() {
            if (window.__grokUsageBoltOpening) return;
            window.__grokUsageBoltOpening = true;
            setTimeout(function() { window.__grokUsageBoltOpening = false; }, 900);

            var actions = findSettingsActions();
            if (actions.setTab && actions.setOpen) {
              try {
                actions.setTab("usage");
                actions.setOpen(true);
                setTimeout(clickUsageNav, 350);
                setTimeout(clickUsageNav, 900);
                scheduleCapture();
                return;
              } catch (e) {}
            }
            assignUsageDeepLink();
          }

          function ensureStyle() {
            if (document.getElementById("grok-native-usage-bolt-style")) return;
            var style = document.createElement("style");
            style.id = "grok-native-usage-bolt-style";
            style.textContent = [
              "[data-grok-usage-name-row]{",
              "display:inline-flex !important;flex-direction:row !important;align-items:center !important;",
              "flex-wrap:nowrap !important;width:auto !important;max-width:100% !important;",
              "min-width:0 !important;vertical-align:middle !important;gap:6px;",
              "}",
              "#grok-native-usage-bolt{",
              "display:inline-flex;align-items:center;justify-content:center;flex:0 0 auto;",
              "box-sizing:border-box;margin:0;padding:0 5px;min-width:22px;height:22px;",
              "border:1px solid rgba(255,255,255,.14);border-radius:6px;",
              "background:rgba(255,255,255,.07);color:rgba(255,255,255,.78);",
              "font:600 14px/20px -apple-system,BlinkMacSystemFont,sans-serif;",
              "cursor:pointer;user-select:none;white-space:nowrap;",
              "transition:background .12s ease,color .12s ease;",
              "}",
              "#grok-native-usage-bolt:hover{background:rgba(255,255,255,.16);color:#fff;}",
              "#grok-native-usage-bolt:focus-visible{outline:2px solid rgba(255,255,255,.7);outline-offset:2px;}",
              "#grok-native-usage-bolt[data-level='warn']{color:#fbbf24;border-color:rgba(251,191,36,.4);}",
              "#grok-native-usage-bolt[data-level='danger']{color:#f87171;border-color:rgba(248,113,113,.45);}"
            ].join("");
            (document.head || document.documentElement).appendChild(style);
          }

          function findNameTextNode(root, name) {
            var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
            var node = null;
            var fallback = null;
            while ((node = walker.nextNode())) {
              if (node.parentElement && node.parentElement.closest && node.parentElement.closest("#grok-native-usage-bolt")) continue;
              var value = (node.textContent || "").replace(/\\s+/g, " ").trim();
              if (value === name) return node;
              if (!fallback && value.indexOf(name) === 0 && value.length < name.length + 8) fallback = node;
            }
            return fallback;
          }

          function ensureNameRow(profile) {
            var existing = profile.el.querySelector("[data-grok-usage-name-row]");
            if (existing) return existing;
            var textNode = findNameTextNode(profile.el, profile.name);
            if (!textNode || !textNode.parentNode) return profile.el;
            var parent = textNode.parentNode;
            var onlyText = true;
            for (var child = parent.firstChild; child; child = child.nextSibling) {
              if (child === textNode) continue;
              if (child.nodeType === 3 && !(child.textContent || "").trim()) continue;
              if (child.id === "grok-native-usage-bolt") continue;
              if (child.nodeType === 1 && child.getAttribute && child.getAttribute("data-grok-usage-name-row")) continue;
              onlyText = false;
              break;
            }
            if (onlyText && parent !== profile.el && parent.children.length <= 1) {
              parent.setAttribute("data-grok-usage-name-row", "1");
              return parent;
            }
            var row = document.createElement("span");
            row.setAttribute("data-grok-usage-name-row", "1");
            parent.insertBefore(row, textNode);
            row.appendChild(textNode);
            return row;
          }

          function attachBolt(profile) {
            ensureStyle();
            var bolt = document.getElementById("grok-native-usage-bolt");
            if (!bolt) {
              bolt = document.createElement("span");
              bolt.id = "grok-native-usage-bolt";
              bolt.setAttribute("role", "button");
              bolt.setAttribute("tabindex", "0");
              bolt.setAttribute("aria-label", "Open usage details");
              bolt.title = "Open usage details";
              bolt.textContent = "\\u03DF";
              var swallow = function(event) {
                event.preventDefault();
                event.stopPropagation();
                if (event.stopImmediatePropagation) event.stopImmediatePropagation();
              };
              ["pointerdown", "mousedown", "pointerup", "mouseup", "click", "contextmenu"].forEach(function(type) {
                bolt.addEventListener(type, function(event) {
                  swallow(event);
                  if (type === "click") openUsageDetails();
                }, true);
              });
              bolt.addEventListener("keydown", function(event) {
                if (event.key === "Enter" || event.key === " ") {
                  swallow(event);
                  openUsageDetails();
                }
              });
            }

            var row = ensureNameRow(profile);
            if (bolt.parentElement !== row) {
              if (bolt.parentElement) bolt.parentElement.removeChild(bolt);
              row.appendChild(bolt);
            }
            return bolt;
          }

          function render() {
            var profile = findProfileHost();
            if (!profile) return;
            var bolt = attachBolt(profile);
            bolt.textContent = state.percent == null ? "\\u03DF" : "\\u03DF " + state.percent + "%";
            bolt.setAttribute("aria-label", state.percent == null ? "Open usage details" : "Open usage details (" + state.percent + "% used)");
            bolt.title = state.percent == null ? "Open usage details" : "Open usage details (" + state.percent + "% used)";
            if (state.percent >= 90) bolt.setAttribute("data-level", "danger");
            else if (state.percent >= 70) bolt.setAttribute("data-level", "warn");
            else bolt.removeAttribute("data-level");
          }

          window.__grokUsageBoltRender = render;
          window.__grokNativeSetUsage = function(payload) {
            if (payload && typeof payload.grokPercent === "number") {
              savePercent(payload.grokPercent);
              render();
            }
          };

          ensureStyle();
          render();
          var observer = new MutationObserver(function() {
            if (window.__grokUsageBoltMOTimer) return;
            window.__grokUsageBoltMOTimer = setTimeout(function() {
              window.__grokUsageBoltMOTimer = null;
              render();
            }, 350);
          });
          try { observer.observe(document.documentElement, { childList: true, subtree: true }); } catch (e) {}
          setInterval(render, REFRESH_MS);
          document.addEventListener("visibilitychange", function() { if (!document.hidden) render(); });
        })();

        """
    }
}
