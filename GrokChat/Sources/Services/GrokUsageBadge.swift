//
//  GrokUsageBadge.swift
//  Grok for Mac
//
//  Adds a compact usage bolt inline to the right of the grok.com sidebar
//  profile name. A hidden offscreen web view re-reads Settings > Usage on a
//  timer and when the app becomes active. The visible page is left alone.
//  Clicking shows a native NSPopover with usage details, while Option-click
//  or Right-click opens Grok's settings Usage tab directly.
//

import Foundation
import WebKit
import SwiftUI
import AppKit
import Intents
import UserNotifications
import Network

extension Notification.Name {
    static let grokUsagePercentDidChange = Notification.Name("grokUsagePercentDidChange")
}

enum GrokUsageBadge {
    static let messageHandlerName = "grokUsageBadge"
    static let refreshIntervalKey = "grok.usageBadgeRefreshSeconds"
    static let percentStorageKey = "grok.usageBadge.percent"
    static let endpointStorageKey = "grok.usageBadge.endpointPath"
    static let updatedAtStorageKey = "grok.usageBadge.updatedAt"
    static let notificationsEnabledKey = "grok.usageNotificationsEnabled"
    static let paceWarningEnabledKey = "grok.usagePaceWarningEnabled"
    static let quietHoursEnabledKey = "grok.quietHours.enabled"
    static let quietHoursStartKey = "grok.quietHours.start"
    static let quietHoursEndKey = "grok.quietHours.end"
    private static let notified80Key = "grok.usageBadge.notified80"
    private static let notified95Key = "grok.usageBadge.notified95"
    private static let lastNotifiedPercentKey = "grok.usageBadge.lastPercent"
    private static let paceWarnedWeekKey = "grok.usageBadge.paceWarnedWeek"
    static let defaultRefreshSeconds = 300 // default ~5 min, clamp 30…3600

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

    /// User script installed at document-start to wrap fetch/XHR before page scripts run.
    static func makeUserScript() -> WKUserScript {
        return WKUserScript(
            source: interceptorJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    /// Helper to install the document-start interceptor into a configuration's userContentController.
    static func installUserScript(into controller: WKUserContentController) {
        controller.addUserScript(makeUserScript())
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
        pushTooltip(into: webView)
    }

    /// Pushes the native pace + reset tooltip (computed in Swift) onto the DOM bolt's
    /// hover title, so hovering the bolt surfaces reset time and pace on/ahead/behind.
    static func pushTooltip(into webView: WKWebView) {
        guard let host = webView.url?.host?.lowercased(),
              host == "grok.com" || host.hasSuffix(".grok.com") else {
            return
        }
        let percent = UserDefaults.standard.object(forKey: percentStorageKey) as? Int
        let tooltip = UsagePaceStore.tooltip(percent: percent)
        guard let data = try? JSONSerialization.data(withJSONObject: [tooltip]),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        let js = """
        (function(){
          window.__grokUsageTooltip = \(json)[0];
          if (typeof window.__grokUsageBoltRender === "function") { window.__grokUsageBoltRender(); }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Kept as a compatibility hook for older settings notifications. Usage is
    /// intentionally owned by grok.com; API-key changes do not alter this UI.
    static func pushAPILabel(_ label: String?, into webView: WKWebView) {
        _ = label
        _ = webView
    }

    // MARK: - Native Popover Handling

    static var currentPopover: NSPopover?

    static var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: notificationsEnabledKey) as? Bool ?? true
    }

    static func checkAndNotifyUsageCrossing(percent: Int) {
        guard notificationsEnabled else { return }

        var notified80 = UserDefaults.standard.bool(forKey: notified80Key)
        var notified95 = UserDefaults.standard.bool(forKey: notified95Key)

        // Reset crossing state if usage drops below thresholds (e.g. usage reset)
        if percent < 80 {
            notified80 = false
            notified95 = false
        } else if percent < 95 {
            notified95 = false
        }

        if percent >= 80 && !notified80 {
            notified80 = true
            postUsageNotification(
                title: "Grok Usage Alert (80%)",
                body: "Grok usage has crossed 80% (\(percent)% used)."
            )
        }

        if percent >= 95 && !notified95 {
            notified95 = true
            postUsageNotification(
                title: "Grok Usage Alert (95%)",
                body: "Grok usage has reached \(percent)% (critical limit: 95%)."
            )
        }

        UserDefaults.standard.set(notified80, forKey: notified80Key)
        UserDefaults.standard.set(notified95, forKey: notified95Key)
        UserDefaults.standard.set(percent, forKey: lastNotifiedPercentKey)
        checkPaceWarning(percent: percent)
    }

    /// Optional alert when usage is more than 15 points ahead of even weekly pacing. Once per calendar week.
    static func checkPaceWarning(percent: Int) {
        guard notificationsEnabled else { return }
        guard UserDefaults.standard.bool(forKey: paceWarningEnabledKey) else { return }
        let ahead = UsagePaceStore.pointsAhead(percent: percent)
        let weekId = paceWeekIdentifier()
        if ahead <= 15 {
            if UserDefaults.standard.string(forKey: paceWarnedWeekKey) == weekId {
                UserDefaults.standard.removeObject(forKey: paceWarnedWeekKey)
            }
            return
        }
        if UserDefaults.standard.string(forKey: paceWarnedWeekKey) == weekId { return }
        UserDefaults.standard.set(weekId, forKey: paceWarnedWeekKey)
        postUsageNotification(
            title: "Grok usage is ahead of pace",
            body: "Usage is \(Int(ahead.rounded())) points ahead of even weekly pacing (\(percent)% used)."
        )
    }

    private static func paceWeekIdentifier(at date: Date = Date()) -> String {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start.timeIntervalSince1970 ?? 0
        return String(Int(start))
    }

    /// True when Focus is on, or the clock is inside the optional quiet-hours window.
    static func notificationsAreSuppressed(at date: Date = Date()) -> Bool {
        if #available(macOS 12.0, *) {
            if INFocusStatusCenter.default.focusStatus.isFocused == true { return true }
        }
        guard UserDefaults.standard.bool(forKey: quietHoursEnabledKey) else { return false }
        let start = UserDefaults.standard.object(forKey: quietHoursStartKey) as? Int ?? 22
        let end = UserDefaults.standard.object(forKey: quietHoursEndKey) as? Int ?? 7
        let hour = Calendar.current.component(.hour, from: date)
        if start == end { return false }
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end
    }

    static func prepareFocusStatus() {
        if #available(macOS 12.0, *) {
            INFocusStatusCenter.default.requestAuthorization { _ in }
        }
    }

    private static func postUsageNotification(title: String, body: String) {
        if notificationsAreSuppressed() { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "grok-usage-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request, withCompletionHandler: nil)
        }
    }

    static func handleScriptMessage(_ message: WKScriptMessage, in webView: WKWebView) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        if action == "showPopover" {
            let x = (body["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (body["y"] as? NSNumber)?.doubleValue ?? 0
            let width = (body["width"] as? NSNumber)?.doubleValue ?? 22
            let height = (body["height"] as? NSNumber)?.doubleValue ?? 22
            let percent = body["percent"] as? Int
            let updatedAtEpoch = (body["updatedAt"] as? NSNumber)?.doubleValue
            let updatedAt = updatedAtEpoch != nil ? Date(timeIntervalSince1970: updatedAtEpoch! / 1000.0) : nil

            if let percent {
                UsagePaceStore.record(percent: percent)
                checkAndNotifyUsageCrossing(percent: percent)
            }

            showPopover(
                anchoredAt: CGRect(x: x, y: y, width: width, height: height),
                percent: percent,
                updatedAt: updatedAt,
                in: webView
            )
        } else if action == "usageUpdated" {
            if let percent = body["percent"] as? Int {
                storeParsedPercent(percent)
            }
        }
    }

    /// Saves a weekly percent that the Settings > Usage parser already accepted.
    static func storeParsedPercent(_ percent: Int) {
        guard (0...100).contains(percent) else { return }
        UserDefaults.standard.set(percent, forKey: percentStorageKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: updatedAtStorageKey)
        UsagePaceStore.record(percent: percent)
        NotificationCenter.default.post(name: .grokUsagePercentDidChange, object: percent)
        checkAndNotifyUsageCrossing(percent: percent)
    }

    static func showPopover(
        anchoredAt rect: CGRect,
        percent: Int?,
        updatedAt: Date?,
        in webView: WKWebView
    ) {
        if let currentPopover, currentPopover.isShown {
            currentPopover.close()
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)

        let contentView = UsagePopoverView(
            percent: percent,
            updatedAt: updatedAt,
            onOpenFullUsage: { [weak webView, weak popover] in
                popover?.close()
                if let webView {
                    openUsageDetails(in: webView)
                }
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        popover.contentViewController = hostingController
        currentPopover = popover

        let positioningRect = webView.isFlipped ? rect : NSRect(
            x: rect.origin.x,
            y: webView.bounds.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        popover.show(relativeTo: positioningRect, of: webView, preferredEdge: .maxX)
    }

    static func openUsageDetails(in webView: WKWebView) {
        webView.evaluateJavaScript("window.__grokUsageOpenDetails ? window.__grokUsageOpenDetails() : window.location.assign('/?_s=usage')", completionHandler: nil)
    }

    // MARK: - JavaScript

    /// Injected at document-start to wrap window.fetch and XMLHttpRequest before grok.com scripts execute.
    private static let interceptorJavaScript: String = """

    (function() {
      if (typeof window === "undefined") return;
      try {
        var host = (window.location && window.location.hostname) ? window.location.hostname.toLowerCase() : "";
        if (host && host !== "grok.com" && !host.endsWith(".grok.com")) return;
      } catch (e) { return; }

      if (window.__grokUsageInterceptorInstalled) return;
      window.__grokUsageInterceptorInstalled = true;

      var PERCENT_KEY = "grok.usageBadge.percent";
      var ENDPOINT_PATH_KEY = "grok.usageBadge.endpointPath";
      var UPDATED_AT_KEY = "grok.usageBadge.updatedAt";
      var CANDIDATE_URL_RE = /(?:rate[-_]?limits?|usage|quota|billing)/i;

      window.__grokUsageState = window.__grokUsageState || {
        percent: null,
        endpointPath: null,
        endpointMethod: "GET",
        updatedAt: null
      };

      function readStoredPercent() {
        try {
          var raw = window.localStorage.getItem(PERCENT_KEY);
          var value = parseInt(raw || "", 10);
          return isFinite(value) && value >= 0 && value <= 100 ? value : null;
        } catch (e) { return null; }
      }

      function readStoredEndpointPath() {
        try {
          var p = window.localStorage.getItem(ENDPOINT_PATH_KEY);
          return (typeof p === "string" && p.length > 0 && p.length < 500) ? p : null;
        } catch (e) { return null; }
      }

      function readStoredUpdatedAt() {
        try {
          var raw = window.localStorage.getItem(UPDATED_AT_KEY);
          var val = parseInt(raw || "", 10);
          return isFinite(val) && val > 0 ? val : null;
        } catch (e) { return null; }
      }

      function savePercent(value) {
        if (!isFinite(value) || value < 0 || value > 100) return;
        var rounded = Math.round(value);
        var now = Date.now();
        window.__grokUsageState.percent = rounded;
        window.__grokUsageState.updatedAt = now;
        try { window.localStorage.setItem(PERCENT_KEY, String(rounded)); } catch (e) {}
        try { window.localStorage.setItem(UPDATED_AT_KEY, String(now)); } catch (e) {}
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.grokUsageBadge) {
          window.webkit.messageHandlers.grokUsageBadge.postMessage({
            action: "usageUpdated",
            percent: rounded,
            updatedAt: now
          });
        }
      }

      function saveEndpoint(urlStr, method) {
        if (!urlStr || typeof urlStr !== "string") return;
        var path = "";
        try {
          var u = new URL(urlStr, window.location.origin);
          path = u.pathname;
        } catch (e) {
          path = urlStr;
        }
        if (!path || path === "/" || path.length < 2) return;

        window.__grokUsageState.endpointPath = path;
        window.__grokUsageState.endpointMethod = (method === "POST") ? "POST" : "GET";
        try { window.localStorage.setItem(ENDPOINT_PATH_KEY, path); } catch (e) {}
      }

      try {
        if (window.localStorage.getItem("grok.usageBadge.percentMigration") !== "1") {
          window.localStorage.removeItem(PERCENT_KEY);
          window.localStorage.setItem("grok.usageBadge.percentMigration", "1");
          window.__grokUsageState.percent = null;
        }
      } catch (e) {}

      if (window.__grokUsageState.percent == null) {
        window.__grokUsageState.percent = readStoredPercent();
      }
      if (!window.__grokUsageState.endpointPath) {
        window.__grokUsageState.endpointPath = readStoredEndpointPath();
      }
      if (!window.__grokUsageState.updatedAt) {
        window.__grokUsageState.updatedAt = readStoredUpdatedAt();
      }

      function isUsageCandidateUrl(urlStr) {
        if (!urlStr || typeof urlStr !== "string") return false;
        if (/\\.(?:js|css|png|jpg|jpeg|gif|svg|webp|woff2?|ttf|eot|ico|map)(?:\\?.*)?$/i.test(urlStr)) return false;
        try {
          var u = new URL(urlStr, window.location.origin);
          var h = u.hostname.toLowerCase();
          if (h !== window.location.hostname.toLowerCase() && !h.endsWith(".grok.com")) return false;
          return CANDIDATE_URL_RE.test(u.pathname);
        } catch (e) {
          return CANDIDATE_URL_RE.test(urlStr);
        }
      }

      function usagePercentFromText(text) {
        if (!text || !/\\busage\\b/i.test(text)) return null;
        // grok.com puts each digit in its own node, so the dialog text is "2\\n1%" for 21%.
        var normalized = String(text).replace(/(\\d)\\s+(?=[\\d.])/g, "$1").replace(/(\\.)\\s+(?=\\d)/g, "$1");
        var found = [];
        var re = /(\\d{1,3}(?:\\.\\d+)?)\\s*%/g;
        var match;
        while ((match = re.exec(normalized)) !== null) {
          var value = Math.round(parseFloat(match[1]));
          if (value < 0 || value > 100) continue;
          var nearby = normalized.slice(Math.max(0, match.index - 90), Math.min(normalized.length, match.index + match[0].length + 90));
          var priority = /\\b(total|overall|combined|weekly)\\b/i.test(nearby) ? 4 : (/%\\s*used|\\bused\\b/i.test(nearby) ? 3 : 1);
          found.push({ value: value, priority: priority, index: match.index });
        }
        if (!found.length) return null;
        var unique = [];
        for (var i = 0; i < found.length; i++) {
          if (unique.indexOf(found[i].value) < 0) unique.push(found[i].value);
        }
        if (unique.length >= 2) {
          var composed = null;
          for (var a = 0; a < unique.length; a++) {
            var rest = 0;
            for (var b = 0; b < unique.length; b++) if (b !== a) rest += unique[b];
            if (Math.abs(rest - unique[a]) <= 2 && (composed == null || unique[a] > composed)) composed = unique[a];
          }
          if (composed != null) return composed;
        }
        found.sort(function(a, b) { return (b.priority - a.priority) || (b.value - a.value) || (a.index - b.index); });
        return found[0].value;
      }

      function extractPercentFromJson(obj) {
        var candidates = [];

        function walk(node, path, depth) {
          if (depth > 6 || !node || typeof node !== "object") return;

          var isWeeklyContext = false;
          var isTotalContext = false;
          for (var prop in node) {
            if (Object.prototype.hasOwnProperty.call(node, prop) && typeof node[prop] === "string") {
              var sVal = node[prop].toLowerCase();
              if (sVal.indexOf("weekly") !== -1) isWeeklyContext = true;
              if (sVal.indexOf("total") !== -1 || sVal.indexOf("overall") !== -1) isTotalContext = true;
            }
          }

          var keys = Object.keys(node);
          for (var i = 0; i < keys.length; i++) {
            var k = keys[i];
            var v = node[k];
            var currentPath = path ? path + "." + k : k;
            var lowerK = k.toLowerCase();

            if (typeof v === "number" || (typeof v === "string" && /^\\s*\\d{1,3}(?:\\.\\d+)?\\s*%?\\s*$/.test(v))) {
              var num = typeof v === "number" ? v : parseFloat(v);
              if (num > 0 && num < 1 && (lowerK.indexOf("percent") !== -1 || lowerK.indexOf("ratio") !== -1 || lowerK.indexOf("rate") !== -1 || lowerK.indexOf("pct") !== -1)) {
                num = Math.round(num * 100);
              } else {
                num = Math.round(num);
              }

              if (num >= 0 && num <= 100) {
                var score = 0;
                var lowerPath = currentPath.toLowerCase();
                if (isWeeklyContext || lowerPath.indexOf("weekly") !== -1) score += 100;
                if (isTotalContext || lowerPath.indexOf("total") !== -1 || lowerPath.indexOf("overall") !== -1) score += 80;
                if (lowerPath.indexOf("ratelimit") !== -1 || lowerPath.indexOf("rate_limit") !== -1 || lowerPath.indexOf("rate-limit") !== -1) score += 60;
                if (lowerPath.indexOf("usage") !== -1 || lowerPath.indexOf("used") !== -1) score += 40;
                if (lowerK.indexOf("percent") !== -1 || lowerK.indexOf("pct") !== -1) score += 50;
                if (lowerK === "creditusagepercent") score += 400;
                if (lowerPath.indexOf("productusage") !== -1) score -= 30;

                var isIgnored = /id|timestamp|created|updated|expires|time|duration|seconds|millis|ms|version|code|status|port|year|month|day|hour|min/i.test(lowerK);
                if (!isIgnored || lowerK.indexOf("percent") !== -1 || lowerK.indexOf("pct") !== -1) {
                  if (score > 0) {
                    candidates.push({ val: num, score: score });
                  }
                }
              }
            }

            if (typeof v === "object" && v !== null && !Array.isArray(v)) {
              var usedVal = null;
              var limitVal = null;
              var remainingVal = null;

              for (var k2 in v) {
                if (!Object.prototype.hasOwnProperty.call(v, k2)) continue;
                var lowerK2 = k2.toLowerCase();
                var val2 = v[k2];
                if (typeof val2 !== "number") continue;

                if (/used|consumed|current|count/i.test(lowerK2) && !/remaining|left|limit|total|max|quota/i.test(lowerK2)) {
                  usedVal = val2;
                } else if (/remaining|left/i.test(lowerK2) && !/used|consumed|limit|total|max|quota/i.test(lowerK2)) {
                  remainingVal = val2;
                } else if (/limit|total|max|quota|cap/i.test(lowerK2) && !/used|consumed|remaining|left/i.test(lowerK2)) {
                  limitVal = val2;
                }
              }

              if (typeof usedVal === "number" && typeof limitVal === "number" && limitVal > 0 && usedVal >= 0) {
                var pct = Math.round((usedVal / limitVal) * 100);
                if (pct >= 0 && pct <= 100) {
                  var s = 60;
                  var lp = currentPath.toLowerCase();
                  if (isWeeklyContext || lp.indexOf("weekly") !== -1) s += 100;
                  if (isTotalContext || lp.indexOf("total") !== -1 || lp.indexOf("overall") !== -1) s += 80;
                  if (lp.indexOf("ratelimit") !== -1 || lp.indexOf("rate-limit") !== -1) s += 50;
                  candidates.push({ val: pct, score: s });
                }
              } else if (typeof remainingVal === "number" && typeof limitVal === "number" && limitVal > 0 && remainingVal >= 0 && remainingVal <= limitVal) {
                var pct2 = Math.round(((limitVal - remainingVal) / limitVal) * 100);
                if (pct2 >= 0 && pct2 <= 100) {
                  var s2 = 50;
                  var lp2 = currentPath.toLowerCase();
                  if (isWeeklyContext || lp2.indexOf("weekly") !== -1) s2 += 100;
                  if (isTotalContext || lp2.indexOf("total") !== -1 || lp2.indexOf("overall") !== -1) s2 += 80;
                  if (lp2.indexOf("ratelimit") !== -1 || lp2.indexOf("rate-limit") !== -1) s2 += 50;
                  candidates.push({ val: pct2, score: s2 });
                }
              }
            }

            if (typeof v === "object" && v !== null) {
              walk(v, currentPath, depth + 1);
            }
          }
        }

        walk(obj, "", 0);

        if (candidates.length > 0) {
          candidates.sort(function(a, b) { return (b.score - a.score) || (b.val - a.val); });
          return candidates[0].val;
        }
        return null;
      }

      function extractPercentFromPayload(payload) {
        if (!payload) return null;
        if (typeof payload === "object") {
          var num = extractPercentFromJson(payload);
          if (num !== null) return num;
          try {
            return usagePercentFromText(JSON.stringify(payload));
          } catch (e) {
            return null;
          }
        }
        if (typeof payload === "string") {
          try {
            var parsed = JSON.parse(payload);
            var n = extractPercentFromJson(parsed);
            if (n !== null) return n;
          } catch (e) {}
          return usagePercentFromText(payload);
        }
        return null;
      }

      function handleUsageResponse(urlStr, method, text) {
        if (!text) return;
        // grok.com billing calls are binary gRPC-web; only trust real JSON bodies.
        var head = String(text).replace(/^\\s+/, "").charAt(0);
        if (head !== "{" && head !== "[") return;
        var percent = extractPercentFromPayload(text);
        if (percent != null) {
          savePercent(percent);
          saveEndpoint(urlStr, method);
          if (typeof window.__grokUsageBoltRender === "function") {
            window.__grokUsageBoltRender();
          }
        }
      }

      var isRefreshing = false;
      function refreshUsage() {
        if (isRefreshing) return;
        var path = (window.__grokUsageState && window.__grokUsageState.endpointPath) || readStoredEndpointPath();
        if (!path) return;
        var method = (window.__grokUsageState && window.__grokUsageState.endpointMethod) || "GET";

        isRefreshing = true;
        try {
          var fetchOpts = {
            method: method,
            credentials: "include"
          };
          if (method === "POST") {
            fetchOpts.headers = { "Content-Type": "application/json" };
            fetchOpts.body = "{}";
          }

          window.__grokUsageIsSelfRefresh = true;
          fetch(path, fetchOpts)
            .then(function(res) {
              window.__grokUsageIsSelfRefresh = false;
              if (!res || !res.ok) return null;
              return res.text();
            })
            .then(function(text) {
              isRefreshing = false;
              if (!text) return;
              var head = String(text).replace(/^\\s+/, "").charAt(0);
              if (head !== "{" && head !== "[") {
                // Learned endpoint is binary gRPC; forget it so we stop polling it.
                try { window.localStorage.removeItem(ENDPOINT_PATH_KEY); } catch (e) {}
                window.__grokUsageState.endpointPath = null;
                return;
              }
              var pct = extractPercentFromPayload(text);
              if (pct != null) {
                savePercent(pct);
                if (typeof window.__grokUsageBoltRender === "function") {
                  window.__grokUsageBoltRender();
                }
              }
            })
            .catch(function() {
              window.__grokUsageIsSelfRefresh = false;
              isRefreshing = false;
            });
        } catch (e) {
          window.__grokUsageIsSelfRefresh = false;
          isRefreshing = false;
        }
      }

      window.__grokUsageRefresh = refreshUsage;

      var origFetch = window.fetch;
      if (typeof origFetch === "function") {
        window.fetch = function(input, init) {
          if (window.__grokUsageIsSelfRefresh) {
            return origFetch.apply(this, arguments);
          }

          var urlStr = "";
          var method = "GET";
          if (typeof input === "string") {
            urlStr = input;
          } else if (input && typeof input.url === "string") {
            urlStr = input.url;
          } else if (input && typeof input.href === "string") {
            urlStr = input.href;
          } else if (input && typeof input.toString === "function") {
            try { urlStr = input.toString(); } catch (e) {}
          }

          if (init && init.method) {
            method = String(init.method).toUpperCase();
          } else if (input && typeof input.method === "string") {
            method = String(input.method).toUpperCase();
          }

          var promise = origFetch.apply(this, arguments);

          if (isUsageCandidateUrl(urlStr)) {
            promise.then(function(res) {
              if (res && res.ok) {
                try {
                  var clone = res.clone();
                  clone.text().then(function(text) {
                    handleUsageResponse(urlStr, method, text);
                  }).catch(function() {});
                } catch (e) {}
              }
            }).catch(function() {});
          }

          return promise;
        };
      }

      if (typeof XMLHttpRequest !== "undefined") {
        var origOpen = XMLHttpRequest.prototype.open;
        var origSend = XMLHttpRequest.prototype.send;

        XMLHttpRequest.prototype.open = function(method, url) {
          this.__grokUsageUrl = url;
          this.__grokUsageMethod = (method || "GET").toUpperCase();
          return origOpen.apply(this, arguments);
        };

        XMLHttpRequest.prototype.send = function() {
          var xhr = this;
          var urlStr = xhr.__grokUsageUrl;
          var method = xhr.__grokUsageMethod || "GET";

          if (isUsageCandidateUrl(urlStr)) {
            xhr.addEventListener("load", function() {
              try {
                if (xhr.status >= 200 && xhr.status < 300) {
                  handleUsageResponse(urlStr, method, xhr.responseText);
                }
              } catch (e) {}
            });
          }

          return origSend.apply(this, arguments);
        };
      }
    })();

    """

    /// bolt-fix-2 weekly parser. The visible bolt and the hidden refresh both use this copy.
    fileprivate static let weeklyPercentParserJavaScript = """
          function weeklyPercentFromUsagePanel(text) {
            if (!text) return null;
            var normalized = String(text).replace(/(\\d)\\s+(?=[\\d.])/g, "$1").replace(/(\\.)\\s+(?=\\d)/g, "$1");
            var start = normalized.search(/weekly\\s+supergrok\\s+limit/i);
            if (start < 0) return null;
            var rest = normalized.slice(start);
            var end = rest.search(/extra usage|additional credits|buy credits/i);
            var section = end > 0 ? rest.slice(0, end) : rest.slice(0, 800);
            var headline = section.match(/(\\d{1,3}(?:\\.\\d+)?)\\s*%\\s*used/i);
            if (!headline) headline = section.match(/\\bused\\s+(\\d{1,3}(?:\\.\\d+)?)\\s*%/i);
            if (headline) {
              var headlineValue = Math.round(parseFloat(headline[1]));
              if (headlineValue >= 0 && headlineValue <= 100) return headlineValue;
            }
            var percentRe = /(\\d{1,3}(?:\\.\\d+)?)\\s*%/g;
            var sum = 0;
            var count = 0;
            var found;
            while ((found = percentRe.exec(section)) !== null) {
              var part = Math.round(parseFloat(found[1]));
              if (part < 0 || part > 100) continue;
              sum += part;
              count += 1;
            }
            if (!count || sum > 100) return null;
            return sum;
          }
"""

    private static func makeInjectorJavaScript(refreshSeconds: Int) -> String {
        return """

        \(interceptorJavaScript)

        (function() {
          var REFRESH_MS = Math.min(3600, Math.max(30, \(refreshSeconds))) * 1000;
          var PERCENT_KEY = "grok.usageBadge.percent";
          var UPDATED_AT_KEY = "grok.usageBadge.updatedAt";
          var state = { percent: null, updatedAt: null };

          function readStoredPercent() {
            try {
              var raw = window.localStorage.getItem(PERCENT_KEY);
              var value = parseInt(raw || "", 10);
              return isFinite(value) && value >= 0 && value <= 100 ? value : null;
            } catch (e) { return null; }
          }

          function readStoredUpdatedAt() {
            try {
              var raw = window.localStorage.getItem(UPDATED_AT_KEY);
              var val = parseInt(raw || "", 10);
              return isFinite(val) && val > 0 ? val : null;
            } catch (e) { return null; }
          }

          function savePercent(value) {
            if (!isFinite(value) || value < 0 || value > 100) return;
            state.percent = Math.round(value);
            state.updatedAt = Date.now();
            if (window.__grokUsageState) {
              window.__grokUsageState.percent = state.percent;
              window.__grokUsageState.updatedAt = state.updatedAt;
            }
            try { window.localStorage.setItem(PERCENT_KEY, String(state.percent)); } catch (e) {}
            try { window.localStorage.setItem(UPDATED_AT_KEY, String(state.updatedAt)); } catch (e) {}
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.grokUsageBadge) {
              window.webkit.messageHandlers.grokUsageBadge.postMessage({
                action: "usageUpdated",
                percent: state.percent,
                updatedAt: state.updatedAt
              });
            }
          }

          state.percent = (window.__grokUsageState && window.__grokUsageState.percent != null)
            ? window.__grokUsageState.percent
            : readStoredPercent();
          state.updatedAt = (window.__grokUsageState && window.__grokUsageState.updatedAt)
            || readStoredUpdatedAt();

          if (state.percent != null && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.grokUsageBadge) {
            window.webkit.messageHandlers.grokUsageBadge.postMessage({
              action: "usageUpdated",
              percent: state.percent,
              updatedAt: state.updatedAt || Date.now()
            });
          }

          if (window.__grokUsageBoltInstalled) {
            window.__grokUsageBoltRender && window.__grokUsageBoltRender();
            if (typeof window.__grokUsageRefresh === "function") {
              window.__grokUsageRefresh();
            }
            return;
          }
          window.__grokUsageBoltInstalled = true;

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

          \(weeklyPercentParserJavaScript)

          function usagePercentFromText(text) {
            var weekly = weeklyPercentFromUsagePanel(text);
            if (weekly != null) return weekly;
            if (!text || !/\\busage\\b/i.test(text)) return null;
            // grok.com puts each digit in its own node, so the dialog text is "2\\n1%" for 21%.
            var normalized = String(text).replace(/(\\d)\\s+(?=[\\d.])/g, "$1").replace(/(\\.)\\s+(?=\\d)/g, "$1");
            var found = [];
            var re = /(\\d{1,3}(?:\\.\\d+)?)\\s*%/g;
            var match;
            while ((match = re.exec(normalized)) !== null) {
              var value = Math.round(parseFloat(match[1]));
              if (value < 0 || value > 100) continue;
              var nearby = normalized.slice(Math.max(0, match.index - 90), Math.min(normalized.length, match.index + match[0].length + 90));
              var priority = /\\b(total|overall|combined|weekly)\\b/i.test(nearby) ? 4 : (/%\\s*used|\\bused\\b/i.test(nearby) ? 3 : 1);
              found.push({ value: value, priority: priority, index: match.index });
            }
            if (!found.length) return null;
            var unique = [];
            for (var i = 0; i < found.length; i++) {
              if (unique.indexOf(found[i].value) < 0) unique.push(found[i].value);
            }
            if (unique.length >= 2) {
              var composed = null;
              for (var a = 0; a < unique.length; a++) {
                var rest = 0;
                for (var b = 0; b < unique.length; b++) if (b !== a) rest += unique[b];
                if (Math.abs(rest - unique[a]) <= 2 && (composed == null || unique[a] > composed)) composed = unique[a];
              }
              if (composed != null) return composed;
            }
            found.sort(function(a, b) { return (b.priority - a.priority) || (b.value - a.value) || (a.index - b.index); });
            return found[0].value;
          }

          function capturePercentFromOpenUsageDialog() {
            var nodes = document.querySelectorAll("[role='dialog'], [aria-modal='true'], [data-state='open']");
            var fallback = null;
            for (var i = 0; i < nodes.length; i++) {
              if (!visible(nodes[i])) continue;
              var text = textOf(nodes[i]);
              var weekly = weeklyPercentFromUsagePanel(text);
              if (weekly != null) { savePercent(weekly); window.__grokUsageBoltRender(); return; }
              if (fallback == null) {
                var value = usagePercentFromText(text);
                if (value != null) fallback = value;
              }
            }
            if (fallback != null) { savePercent(fallback); window.__grokUsageBoltRender(); }
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
              if (fiber.child) stack.child && stack.push(fiber.child);
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

          window.__grokUsageOpenDetails = openUsageDetails;

          function showUsagePopover(el) {
            var rect = (el && el.getBoundingClientRect) ? el.getBoundingClientRect() : { left: 0, top: 0, width: 22, height: 22 };
            var currentPercent = (window.__grokUsageState && window.__grokUsageState.percent != null)
              ? window.__grokUsageState.percent
              : state.percent;
            var currentUpdatedAt = (window.__grokUsageState && window.__grokUsageState.updatedAt)
              || state.updatedAt
              || readStoredUpdatedAt();

            var payload = {
              action: "showPopover",
              x: rect.left,
              y: rect.top,
              width: rect.width,
              height: rect.height,
              percent: currentPercent,
              updatedAt: currentUpdatedAt
            };

            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.grokUsageBadge) {
              window.webkit.messageHandlers.grokUsageBadge.postMessage(payload);
            }
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
              "#grok-native-usage-bolt[data-level='good']{color:#4ade80;border-color:rgba(74,222,128,.4);}",
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
                  if (type === "click") {
                    if (event.altKey) {
                      openUsageDetails();
                    } else {
                      showUsagePopover(bolt);
                    }
                  } else if (type === "contextmenu") {
                    openUsageDetails();
                  }
                }, true);
              });
              bolt.addEventListener("keydown", function(event) {
                if (event.key === "Enter" || event.key === " ") {
                  swallow(event);
                  if (event.altKey) openUsageDetails();
                  else showUsagePopover(bolt);
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
            if (usageDetailIsOpen()) {
              var now = Date.now();
              if (!window.__grokUsageCaptureAt || now - window.__grokUsageCaptureAt > 1500) {
                window.__grokUsageCaptureAt = now;
                capturePercentFromOpenUsageDialog();
              }
            }
            var profile = findProfileHost();
            if (!profile) return;
            var bolt = attachBolt(profile);
            var currentPercent = (window.__grokUsageState && window.__grokUsageState.percent != null)
              ? window.__grokUsageState.percent
              : state.percent;
            bolt.textContent = currentPercent == null ? "\\u03DF" : "\\u03DF " + currentPercent + "%";
            var usageLabel = currentPercent == null ? "Open usage details" : "Open usage details (" + currentPercent + "% used)";
            bolt.setAttribute("aria-label", usageLabel);
            // Prefer the native pace + reset tooltip Swift pushes; fall back to the usage label.
            bolt.title = (typeof window.__grokUsageTooltip === "string" && window.__grokUsageTooltip.length > 0)
              ? window.__grokUsageTooltip
              : usageLabel;
            if (currentPercent != null) {
              if (currentPercent > 85) bolt.setAttribute("data-level", "danger");
              else if (currentPercent >= 60) bolt.setAttribute("data-level", "warn");
              else bolt.setAttribute("data-level", "good");
            } else {
              bolt.removeAttribute("data-level");
            }
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
          scheduleCapture();
          var observer = new MutationObserver(function() {
            if (window.__grokUsageBoltMOTimer) return;
            window.__grokUsageBoltMOTimer = setTimeout(function() {
              window.__grokUsageBoltMOTimer = null;
              render();
            }, 350);
          });
          try { observer.observe(document.documentElement, { childList: true, subtree: true }); } catch (e) {}

          setInterval(function() {
            if (typeof window.__grokUsageRefresh === "function") {
              window.__grokUsageRefresh();
            }
            render();
          }, REFRESH_MS);

          document.addEventListener("visibilitychange", function() {
            if (!document.hidden) {
              if (typeof window.__grokUsageRefresh === "function") {
                window.__grokUsageRefresh();
              }
              render();
            }
          });

          // Trigger immediate refresh after page loads
          if (typeof window.__grokUsageRefresh === "function") {
            window.__grokUsageRefresh();
            setTimeout(window.__grokUsageRefresh, 1500);
          }
        })();

        """
    }
}

/// Offscreen host for the usage refresh. It cannot become key, so it does not steal the visible window.
final class UsageBoltOffscreenWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Hidden Settings > Usage refresh

/// Loads grok.com Settings > Usage in an offscreen web view that shares the main login store.
/// The visible grok.com page is not navigated. The hidden view is closed after each attempt.
final class UsageBoltAutoRefresh: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = UsageBoltAutoRefresh()

    static let refreshInterval: TimeInterval = 15 * 60
    /// Probes of one hidden page. A cycle ends when one succeeds or this many have run.
    static let maxProbeAttempts = 6
    /// Full loads of the usage URL in one cycle, including the first.
    static let maxLoads = 2
    /// Collapses a burst of become-active notifications. The 15-minute timer is unaffected.
    static let activationBurstGap: TimeInterval = 20

    private let usageURL = URL(string: "https://grok.com/?_s=usage")!
    private let probeDelays: [TimeInterval] = [0.8, 1.8, 3.2, 5.0, 7.5, 10.5]
    private let networkQueue = DispatchQueue(label: "grok.usage-bolt.network")

    private var visibleWebViews: () -> [WKWebView] = { [] }
    private var started = false
    private var timer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var sawPath = false
    private var isOnline = false
    private var isAsleep = false
    private var pendingRefresh = false
    private var inFlight = false
    private var generation = 0
    private var loads = 0
    private var probesScheduled = false
    private var didForceUsageURL = false
    private var lastActivationAt: Date?
    private var sleepObservers: [NSObjectProtocol] = []
    private var webView: WKWebView?
    private var hostWindow: NSWindow?

    func start(visibleWebViews: @escaping () -> [WKWebView]) {
        self.visibleWebViews = visibleWebViews
        guard !started else { return }
        started = true

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                let online = path.status == .satisfied
                let first = !self.sawPath
                self.sawPath = true
                self.isOnline = online
                if first, self.pendingRefresh {
                    self.pendingRefresh = false
                    self.begin(reason: "deferred")
                }
            }
        }
        monitor.start(queue: networkQueue)
        pathMonitor = monitor

        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.isAsleep = true
                if self.inFlight { self.finish(percent: nil) }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.isAsleep = false
            }
        ]

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.begin(reason: "interval")
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshBecauseActive()
    }

    /// Refresh because Grok became the active app. Skipped while a cycle is already running.
    func refreshBecauseActive() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let lastActivationAt, Date().timeIntervalSince(lastActivationAt) < Self.activationBurstGap {
                return
            }
            self.lastActivationAt = Date()
            self.begin(reason: "active")
        }
    }

    private func begin(reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        if !sawPath {
            pendingRefresh = true
            return
        }
        if isAsleep || !isOnline || inFlight { return }
        inFlight = true
        generation += 1
        loads = 0
        probesScheduled = false
        didForceUsageURL = false
        openHiddenPage()
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.inFlight, self.generation == token else { return }
            self.finish(percent: nil)
        }
        _ = reason
    }

    private func openHiddenPage() {
        tearDownWebView()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        let window = UsageBoltOffscreenWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 1280, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.sharingType = .none
        window.collectionBehavior = [.ignoresCycle, .transient, .stationary]
        window.contentView = webView
        let keyWindow = NSApp.keyWindow
        window.orderFrontRegardless()
        keyWindow?.orderFront(nil)

        self.webView = webView
        hostWindow = window
        loadUsagePage()
    }

    private func loadUsagePage() {
        guard inFlight, let webView else { return }
        loads += 1
        if loads > Self.maxLoads {
            finish(percent: nil)
            return
        }
        probesScheduled = false
        webView.load(URLRequest(url: usageURL))
    }

    private func scheduleProbes() {
        guard !probesScheduled else { return }
        probesScheduled = true
        let token = generation
        for (index, delay) in probeDelays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.probe(index: index, token: token)
            }
        }
    }

    private func probe(index: Int, token: Int) {
        guard inFlight, generation == token, index < Self.maxProbeAttempts, let webView else { return }
        if isAsleep || !isOnline {
            finish(percent: nil)
            return
        }
        let script = Self.probeScript(shouldOpen: index < 3)
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self, self.inFlight, self.generation == token else { return }
                if let percent = self.percent(from: result) {
                    self.finish(percent: percent)
                } else if index + 1 >= Self.maxProbeAttempts {
                    self.finish(percent: nil)
                }
            }
        }
    }

    private func percent(from result: Any?) -> Int? {
        guard let number = result as? NSNumber else { return nil }
        let value = number.intValue
        return (0...100).contains(value) ? value : nil
    }

    private func finish(percent: Int?) {
        guard inFlight else { return }
        inFlight = false
        generation += 1
        if let percent {
            GrokUsageBadge.storeParsedPercent(percent)
            publishToVisibleBolts(percent)
        }
        tearDownWebView()
    }

    /// Updates the bolt already drawn on grok.com. Does not navigate or click that page.
    private func publishToVisibleBolts(_ percent: Int) {
        let script = """
        (function() {
          if (window.__grokUsageState) {
            window.__grokUsageState.percent = \(percent);
            window.__grokUsageState.updatedAt = Date.now();
          }
          if (typeof window.__grokUsageBoltRender === "function") window.__grokUsageBoltRender();
        })();
        """
        for view in visibleWebViews() {
            guard let host = view.url?.host?.lowercased(),
                  host == "grok.com" || host.hasSuffix(".grok.com") else { continue }
            view.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func tearDownWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        hostWindow?.orderOut(nil)
        hostWindow?.contentView = nil
        hostWindow?.close()
        webView = nil
        hostWindow = nil
    }

    private static func isGrokHost(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "grok.com" || host.hasSuffix(".grok.com")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard inFlight, webView === self.webView, Self.isGrokHost(webView.url) else { return }
        let onUsage = URLComponents(url: webView.url ?? usageURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains { $0.name == "_s" && $0.value == "usage" } ?? false
        if !onUsage && !didForceUsageURL {
            didForceUsageURL = true
            webView.evaluateJavaScript("window.location.assign('https://grok.com/?_s=usage')", completionHandler: nil)
            return
        }
        scheduleProbes()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        noteLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        noteLoadFailure(error)
    }

    private func noteLoadFailure(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        guard inFlight else { return }
        if probesScheduled || loads >= Self.maxLoads {
            finish(percent: nil)
            return
        }
        loadUsagePage()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// Reads the open usage panel with the bolt-fix-2 parser. `shouldOpen` asks the page to show Usage first.
    private static func probeScript(shouldOpen: Bool) -> String {
        let openFlag = shouldOpen ? "true" : "false"
        return """
        (function() {
          \(GrokUsageBadge.weeklyPercentParserJavaScript)
          function visible(el) {
            if (!el || !el.isConnected) return false;
            var style = window.getComputedStyle(el);
            var rect = el.getBoundingClientRect();
            return style.display !== "none" && style.visibility !== "hidden" &&
              parseFloat(style.opacity || "1") > 0 && rect.width > 0 && rect.height > 0;
          }
          function textOf(el) {
            if (!el) return "";
            return ((el.innerText || el.textContent || "") + "").replace(/\\s+/g, " ").trim();
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
          function clickUsageNav() {
            var buttons = document.querySelectorAll("[data-settings-nav-button], button, a, [role='button']");
            for (var i = 0; i < buttons.length; i++) {
              if (!visible(buttons[i])) continue;
              var label = textOf(buttons[i]).toLowerCase();
              if (label !== "usage") continue;
              var selected = buttons[i].getAttribute("data-settings-nav-selected");
              if (selected == null) clickElement(buttons[i]);
              return true;
            }
            return false;
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
          function openUsagePanel() {
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
            if (fiberKey && seed[fiberKey]) {
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
            }
            if (setTab && setOpen) {
              try { setTab("usage"); setOpen(true); } catch (e) {}
            }
            clickUsageNav();
          }
          function readWeekly() {
            var nodes = document.querySelectorAll("[role='dialog'], [aria-modal='true'], [data-state='open']");
            for (var i = 0; i < nodes.length; i++) {
              if (!visible(nodes[i])) continue;
              var weekly = weeklyPercentFromUsagePanel(textOf(nodes[i]));
              if (weekly != null) return weekly;
            }
            return weeklyPercentFromUsagePanel(textOf(document.body));
          }
          if (\(openFlag)) openUsagePanel();
          var weekly = readWeekly();
          if (weekly == null) return null;
          try {
            localStorage.setItem("grok.usageBadge.percent", String(weekly));
            localStorage.setItem("grok.usageBadge.updatedAt", String(Date.now()));
          } catch (e) {}
          return weekly;
        })();
        """
    }
}

// MARK: - Weekly pace samples

enum UsagePaceStore {
    struct Sample: Codable, Equatable {
        var t: TimeInterval
        var percent: Int
    }

    static let samplesKey = "grok.usageBadge.samples"
    private static let retention: TimeInterval = 14 * 24 * 60 * 60
    private static let minGap: TimeInterval = 15 * 60

    static func record(percent: Int, at date: Date = Date()) {
        let now = date.timeIntervalSince1970
        var samples = load().filter { now - $0.t <= retention }
        if let last = samples.last, last.percent == percent, now - last.t < minGap {
            return
        }
        samples.append(Sample(t: now, percent: percent))
        if let data = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(data, forKey: samplesKey)
        }
    }

    static func samples(now: Date = Date()) -> [Sample] {
        let cutoff = now.timeIntervalSince1970 - retention
        return load().filter { $0.t >= cutoff }.sorted { $0.t < $1.t }
    }

    /// Percent used if the weekly quota were spent evenly from the start of this calendar week.
    static func expectedPercent(at date: Date = Date()) -> Double {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        let week = interval.duration
        guard week > 0 else { return 0 }
        let elapsed = min(max(0, date.timeIntervalSince(interval.start)), week)
        return (elapsed / week) * 100
    }

    static func pointsAhead(percent: Int, at date: Date = Date()) -> Double {
        Double(percent) - expectedPercent(at: date)
    }

    /// Where usage sits relative to even weekly pacing.
    enum PaceState: Equatable {
        case onPace
        case ahead
        case behind

        /// Short human label, e.g. "on pace" / "ahead of pace" / "behind pace".
        var label: String {
            switch self {
            case .onPace: return "on pace"
            case .ahead: return "ahead of pace"
            case .behind: return "behind pace"
            }
        }
    }

    /// Three-state pace relative to even weekly pacing. Within ±0.5 points counts as on pace.
    static func paceState(percent: Int, at date: Date = Date()) -> PaceState {
        let ahead = pointsAhead(percent: percent, at: date)
        if ahead > 0.5 { return .ahead }
        if ahead < -0.5 { return .behind }
        return .onPace
    }

    static func paceLabel(percent: Int, at date: Date = Date()) -> String {
        paceState(percent: percent, at: date).label
    }

    /// When the current weekly quota resets (end of this calendar week).
    static func resetDate(at date: Date = Date()) -> Date? {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.end
    }

    /// Human text for the weekly reset, e.g. "Resets in 2 days (Mon)".
    static func resetDescription(at date: Date = Date()) -> String {
        guard let reset = resetDate(at: date) else { return "Weekly reset time unknown" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        let weekday = DateFormatter()
        weekday.setLocalizedDateFormatFromTemplate("EEE")
        return "Resets \(relative.localizedString(for: reset, relativeTo: date)) (\(weekday.string(from: reset)))"
    }

    /// One-line tooltip combining pace and the weekly reset, e.g.
    /// "72% used · ahead of pace · Resets in 2 days (Mon)".
    static func tooltip(percent: Int?, at date: Date = Date()) -> String {
        let reset = resetDescription(at: date)
        let scope = "Grok, Grok Bot & Terminal"
        guard let percent else {
            return "Usage unknown · \(scope) · \(reset)"
        }
        return "\(percent)% used · \(scope) · \(paceState(percent: percent, at: date).label) · \(reset)"
    }

    private static func load() -> [Sample] {
        guard let data = UserDefaults.standard.data(forKey: samplesKey),
              let decoded = try? JSONDecoder().decode([Sample].self, from: data) else {
            return []
        }
        return decoded
    }
}

private struct UsageSparkline: View {
    let samples: [UsagePaceStore.Sample]

    var body: some View {
        GeometryReader { geo in
            let points = points(in: geo.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 36)
        .accessibilityLabel("Usage over the last 14 days")
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        if samples.count == 1, let only = samples.first {
            let y = yPosition(percent: only.percent, height: size.height)
            return [CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y)]
        }
        let minT = samples[0].t
        let maxT = samples[samples.count - 1].t
        let span = max(maxT - minT, 1)
        return samples.map { sample in
            CGPoint(
                x: CGFloat((sample.t - minT) / span) * size.width,
                y: yPosition(percent: sample.percent, height: size.height)
            )
        }
    }

    private func yPosition(percent: Int, height: CGFloat) -> CGFloat {
        let clamped = CGFloat(min(100, max(0, percent))) / 100
        return height * (1 - clamped)
    }
}

// MARK: - Native Popover View

struct UsagePopoverView: View {
    let percent: Int?
    let updatedAt: Date?
    let onOpenFullUsage: () -> Void

    private var paceSamples: [UsagePaceStore.Sample] {
        UsagePaceStore.samples()
    }

    private var statusColor: Color {
        guard let percent else { return .secondary }
        if percent > 85 {
            return Color(red: 0.97, green: 0.44, blue: 0.44)
        } else if percent >= 60 {
            return Color(red: 0.98, green: 0.75, blue: 0.14)
        } else {
            return Color(red: 0.29, green: 0.87, blue: 0.50)
        }
    }

    private var updatedString: String {
        guard let updatedAt else { return "Last updated: Not yet cached" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Last updated " + formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    private func paceLine(for percent: Int) -> String {
        let expected = Int(UsagePaceStore.expectedPercent().rounded())
        return "\(UsagePaceStore.paceLabel(percent: percent)) · even pace \(expected)%"
    }

    private func paceAccessibility(for percent: Int) -> String {
        let expected = Int(UsagePaceStore.expectedPercent().rounded())
        return "\(UsagePaceStore.paceLabel(percent: percent)), even weekly pace \(expected) percent"
    }

    private var resetString: String {
        UsagePaceStore.resetDescription()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("ϟ")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    if let percent {
                        Text("\(percent)% Used")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                    } else {
                        Text("Usage Unknown")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Text(updatedString)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            UsageSparkline(samples: paceSamples)
                .padding(.vertical, 2)

            if let percent {
                Text(paceLine(for: percent))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .accessibilityLabel(paceAccessibility(for: percent))
            }

            Text(resetString)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Divider()

            Button(action: onOpenFullUsage) {
                HStack {
                    Text("Open full Usage")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 220)
    }
}
