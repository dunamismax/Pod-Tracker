# Pod Tester Quick Start

1. Open `/login`.
2. Enter your email to request a 6-digit OTP.
3. Open your mailbox and copy the code.
4. Open `/verify`, enter email + code, then sign in.
5. On the dashboard:
   - Create a pod.
   - Confirm the pod appears under "Your pods".
6. Hit API endpoints while signed in:
   - `GET /api/pods`
   - `GET /api/events`
7. Sign out from the header and re-test `GET /api/pods`; it should return `401`.
