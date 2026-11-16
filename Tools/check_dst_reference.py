#!/usr/bin/env python3
"""Check Swift's parity fixtures against IANA's fold=0 (Java atZone policy).
Optionally evaluate the same cases with a real JDK. Does not execute Swift or Android.
"""
import argparse
from datetime import datetime, time, timedelta, timezone
from pathlib import Path
import re
import shutil
import subprocess
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
def instant(value): return datetime.fromisoformat(value.replace('Z', '+00:00'))
def reference(zone_name, start, after):
    zone = ZoneInfo(zone_name)
    local_start = start.astimezone(zone)
    first = max(start, after).astimezone(zone).date()
    clock = time(local_start.hour, local_start.minute)
    for offset in range(8):
        day = first + timedelta(days=offset)
        if day.isoweekday() != 7: continue
        # fold=0 uses the earlier instant for overlaps and the pre-gap offset
        # for missing times: the same resolution rule as Java LocalDateTime.atZone.
        candidate = datetime.combine(day, clock).replace(tzinfo=zone, fold=0).astimezone(timezone.utc)
        if candidate >= start and candidate > after: return candidate
    raise AssertionError('Reference has no next Sunday')

def fixtures():
    source = (ROOT/'Tests/CoreTests.swift').read_text()
    section = source.split('func testWeeklyMatchesAndroidAtZoneReferenceCases()', 1)[1]
    section = section.split('func testIdentityMismatchStopsBeforeUpload()', 1)[0]
    pattern = r'\("([^"]+)", "([^"]+)", "([^"]+)", "([^"]+)"\)'
    rows = re.findall(pattern, section)
    assert len(rows) == 6, 'Parity fixture list changed: review coverage before running'
    return rows

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--java', help='Path to a JDK 11+ java executable (optional)')
    args = parser.parse_args()
    java = args.java or shutil.which('java')
    for zone, start, after, expected in fixtures():
        actual = reference(zone, instant(start), instant(after))
        assert actual == instant(expected), f'IANA reference disagrees: {zone}'
        if java:
            command = [java, str(ROOT/'Tools/AndroidWeeklyOracle.java'), zone, start, after, '7', '1']
            result = subprocess.check_output(command, text=True).strip()
            assert instant(result) == instant(expected), f'Java atZone disagrees: {zone}'
        print(f'PASS: {zone} -> {expected}')
    print('PASS: 6 IANA policy reference cases; fixtures themselves are exercised by XCTest in Codemagic.')
    print('PASS: 6 actual Java atZone cases.' if java else 'SKIP: no JDK available; Java oracle not executed.')
    print('Swift/XCTest and Android APK execution are NOT performed by this script.')
if __name__ == '__main__': main()
