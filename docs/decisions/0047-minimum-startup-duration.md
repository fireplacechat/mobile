# 0047: Keep normal startup visible for at least three seconds

Issue #148 asks for enough time to see the existing startup animation. Normal
launch now keeps the approved splash until both three seconds have elapsed and
the existing destination is ready. The timer belongs to the mounted AuthGate;
authentication, session initialization and chat-list warmup begin immediately
and run alongside it. A five-second startup still takes five seconds, rather
than adding three seconds after loading.

The minimum applies to the normal sign-in and chat-list destinations. Startup
errors, device recovery and pending account deletion remain immediately
actionable. Session refresh still hides stale recovery/error actions while
initializing, as in 0046. Navigation, rebuilds, resume and sign-out do not restart
the minimum; disposal cancels its timer. Reduced-motion preferences continue to
disable firefly animation without changing the minimum duration.

This changes presentation timing only. Authentication, keys, recovery, session
ownership and encrypted storage are unchanged. There are no added reads, writes,
network calls, fields, dependencies or permissions, and no Firebase cost change.

Widget tests advance a fake clock to the three-second boundary, verify eager
session/warmup work and slow readiness, and cover navigation/resume/sign-out,
actionable errors and timer disposal. Existing recovery, deletion and refresh
regressions remain required. Render cases capture the real gate at 2.5 seconds
and its ready destination after the minimum, in both themes.

Implementation assisted by OpenAI Codex.
