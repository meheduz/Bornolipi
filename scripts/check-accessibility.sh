#!/bin/bash
# Static accessibility checks for the SwiftUI views (part of lint). A VoiceOver pass by hand is
# optional (not a release blocker); this catches the mistakes that are easy to reintroduce:
#   - a button whose only label is an icon must say what it does (.accessibilityLabel)
#   - a decorative or symbolic icon outside a Label must be hidden or labelled
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
for f in Sources/Bornolipi/*.swift Sources/BornolipiKeyboard/*.swift; do
    # Icon-only buttons: "label: { Image(systemName:" not followed by an accessibility label within 2 lines.
    while IFS=: read -r n _; do
        [ -z "$n" ] && continue
        if ! sed -n "${n},$((n + 2))p" "$f" | grep -q 'accessibilityLabel'; then
            echo "  $f:$n: icon-only button without .accessibilityLabel"; fail=1
        fi
    done < <(grep -n 'label: { Image(systemName:' "$f")
    # Standalone icons: Image(systemName:) not inside a Label/label: and not hidden or labelled nearby.
    while IFS=: read -r n _; do
        [ -z "$n" ] && continue
        line="$(sed -n "${n}p" "$f")"
        echo "$line" | grep -qE 'Label|label:|icon:' && continue
        if ! sed -n "$((n > 5 ? n - 5 : 1)),$((n + 3))p" "$f" | grep -qE 'accessibilityHidden|accessibilityLabel|accessibilityElement\(children: \.(ignore|combine)\)|icon:'; then
            echo "  $f:$n: icon without accessibility handling"; fail=1
        fi
    done < <(grep -n 'Image(systemName:' "$f")
done
[ $fail = 0 ] && echo "    no accessibility findings" || echo "Accessibility check FAILED."
exit $fail
