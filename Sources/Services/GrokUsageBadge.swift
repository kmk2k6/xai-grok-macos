//
//  GrokUsageBadge.swift
//  Grok for Mac
//
//  Compact usage bolt on the same row as the grok.com sidebar profile name.
//  One click hard-loads the current page with ?_s=usage. Grok's settings store
//  reads that param only in its constructor, so a soft history update does not
//  open Usage. Do not walk Account / Payments menus.
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
            return (el.innerText || el.textContent || "").replace(/\\s+/g, " ").trim();
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
              var raw = textOf(el);
              if (!raw) continue;
              var lines = (el.innerText || "").split("\\n").map(function(x) { return x.trim(); }).filter(Boolean);
              var name = lines[0] || raw;
              if (name.length < 2 || name.length > 48 || skipName(name)) continue;
              if (/^\\d+%/.test(name) || /usage|api|payments|general/i.test(name)) continue;
              var score = rect.bottom;
              if (el.querySelector("img")) score += 80;
              if (/\\s/.test(name)) score += 40;
              if (!best || score > best.score) best = { el: el, name: name, score: score };
            }
            return best;
          }

          function usagePercentFromText(text) {
            if (!text || !/\\busage\\b/i.test(text)) return null;
            var matches = [];
            var re = /(\\d{1,3})\\s*%/g;
            var match;
            while ((match = re.exec(text)) !== null) {
              var value = parseInt(match[1], 10);
              if (value < 0 || value > 100) continue;
              var nearby = text.slice(Math.max(0, match.index - 90), Math.min(text.length, match.index + match[0].length + 90));
              var priority = /\\b(total|overall|summary)\\b/i.test(nearby) ? 3 : (/\\bused\\b/i.test(nearby) ? 2 : 1);
              matches.push({ value: value, priority: priority });
            }
            if (!matches.length) return null;
            matches.sort(function(a, b) { return b.priority - a.priority; });
            return matches[0].value;
          }

          function capturePercentFromOpenUsageDialog() {
            var nodes = document.querySelectorAll("[role='dialog'], [aria-modal='true'], [data-state='open'], [data-radix-popper-content-wrapper]");
            for (var i = 0; i < nodes.length; i++) {
              if (!visible(nodes[i])) continue;
              var value = usagePercentFromText(textOf(nodes[i]));
              if (value != null) { savePercent(value); window.__grokUsageBoltRender(); return; }
            }
          }

          function scheduleCapture() {
            setTimeout(capturePercentFromOpenUsageDialog, 450);
            setTimeout(capturePercentFromOpenUsageDialog, 1100);
            setTimeout(capturePercentFromOpenUsageDialog, 2200);
          }

          function openUsageDetails() {
            if (window.__grokUsageBoltOpening) return;
            window.__grokUsageBoltOpening = true;
            // Keep the open chat. Only the settings query changes.
            // A full load is required: useSettingsDialogStore applies _s
            // once, in its constructor. history.replaceState will not open it.
            var target = new URL(window.location.href);
            target.hash = "";
            var already = target.searchParams.get("_s") === "usage";
            target.searchParams.set("_s", "usage");
            if (already) {
              window.location.reload();
              return;
            }
            window.location.assign(target.toString());
          }

          function ensureStyle() {
            if (document.getElementById("grok-native-usage-bolt-style")) return;
            var style = document.createElement("style");
            style.id = "grok-native-usage-bolt-style";
            style.textContent = [
              "#grok-native-usage-bolt{",
              "display:inline-flex;align-items:center;justify-content:center;",
              "box-sizing:border-box;flex:0 0 auto;align-self:center;",
              "margin:0 0 0 8px;padding:0 5px;min-width:22px;height:22px;",
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

          function swallow(event) {
            event.preventDefault();
            event.stopPropagation();
            if (event.stopImmediatePropagation) event.stopImmediatePropagation();
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
              bolt.textContent = "\u03df";
              bolt.addEventListener("pointerdown", function(event) {
                swallow(event);
                openUsageDetails();
              }, true);
              bolt.addEventListener("mousedown", swallow, true);
              bolt.addEventListener("click", swallow, true);
              bolt.addEventListener("keydown", function(event) {
                if (event.key === "Enter" || event.key === " ") {
                  swallow(event);
                  openUsageDetails();
                }
              }, true);
            }

            var nameEl = null;
            var kids = profile.el.querySelectorAll("span, div, p");
            for (var i = 0; i < kids.length; i++) {
              var childText = textOf(kids[i]);
              if (childText === profile.name || childText.indexOf(profile.name) === 0) {
                nameEl = kids[i];
                break;
              }
            }
            var line = nameEl || profile.el;
            line.style.display = "flex";
            line.style.alignItems = "center";
            line.style.flexWrap = "nowrap";
            line.style.width = "100%";
            line.style.minWidth = "0";
            line.style.gap = "6px";
            if (bolt.parentElement !== line) {
              if (bolt.parentElement) bolt.parentElement.removeChild(bolt);
              line.appendChild(bolt);
            }
            return bolt;
          }

          function render() {
            var profile = findProfileHost();
            if (!profile) return;
            var bolt = attachBolt(profile);
            bolt.textContent = state.percent == null ? "\u03df" : "\u03df " + state.percent + "%";
            bolt.setAttribute("aria-label", state.percent == null ? "Open usage details" : "Open usage details (" + state.percent + "% used)");
            bolt.title = state.percent == null ? "Open usage details" : "Open usage details (" + state.percent + "% used)";
            if (state.percent != null && state.percent >= 90) bolt.setAttribute("data-level", "danger");
            else if (state.percent != null && state.percent >= 70) bolt.setAttribute("data-level", "warn");
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
          try {
            if (new URL(window.location.href).searchParams.get("_s") === "usage") scheduleCapture();
          } catch (e) {}
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
