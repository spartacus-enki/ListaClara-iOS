import java.time.*;
import java.util.*;

/** Read-only reference for Events.kt nextAfter/preview's WEEKLY branch.
 * Run with a JDK 11+: java Tools/AndroidWeeklyOracle.java ZONE START AFTER WEEKDAYS LIMIT
 * No Gradle invocation, Android checkout access, database or application writes.
 */
class AndroidWeeklyOracle {
    public static void main(String[] args) {
        if (args.length != 5) throw new IllegalArgumentException("ZONE START_ISO AFTER_ISO ISO_WEEKDAYS_CSV LIMIT");
        ZoneId zone = ZoneId.of(args[0]);
        Instant start = Instant.parse(args[1]);
        Instant after = Instant.parse(args[2]);
        LocalTime clock = start.atZone(zone).toLocalTime().withSecond(0).withNano(0);
        Set<Integer> weekdays = new HashSet<>();
        for (String day : args[3].split(",")) weekdays.add(Integer.parseInt(day));
        int limit = Integer.parseInt(args[4]);
        if (limit < 1 || weekdays.isEmpty() || weekdays.stream().anyMatch(x -> x < 1 || x > 7)) {
            throw new IllegalArgumentException("Invalid weekdays or limit");
        }
        for (int index = 0; index < limit; index++) {
            LocalDate first = (after.isAfter(start) ? after : start).atZone(zone).toLocalDate();
            Instant found = null;
            for (int day = 0; day <= 7; day++) {
                LocalDate date = first.plusDays(day);
                if (!weekdays.contains(date.getDayOfWeek().getValue())) continue;
                Instant candidate = date.atTime(clock).atZone(zone).toInstant();
                if (!candidate.isBefore(start) && candidate.isAfter(after)) { found = candidate; break; }
            }
            if (found == null) break;
            System.out.println(found);
            after = found;
        }
    }
}
