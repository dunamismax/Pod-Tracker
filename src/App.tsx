import { QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter, Navigate, Outlet, Route, Routes } from 'react-router-dom';

import { queryClient } from '@/lib/queryClient';
import { SessionProvider, useSession } from '@/web/session-context';
import { AppLayout } from '@/web/components/app-layout';
import { AuthCallbackPage } from '@/web/pages/auth-callback-page';
import { AuthPage } from '@/web/pages/auth-page';
import { CreateEventPage } from '@/web/pages/create-event-page';
import { CreatePodPage } from '@/web/pages/create-pod-page';
import { EventDetailPage } from '@/web/pages/event-detail-page';
import { EventEditPage } from '@/web/pages/event-edit-page';
import { HomePage } from '@/web/pages/home-page';
import { InvitesPage } from '@/web/pages/invites-page';
import { NotificationsPage } from '@/web/pages/notifications-page';
import { PodDetailPage } from '@/web/pages/pod-detail-page';
import { PodsPage } from '@/web/pages/pods-page';

function RequireAuthRoute() {
  const { user, isLoading } = useSession();

  if (isLoading) {
    return (
      <section className="panel">
        <p className="muted">Checking session...</p>
      </section>
    );
  }

  if (!user) {
    return <Navigate to="/auth" replace />;
  }

  return <Outlet />;
}

function FallbackRoute() {
  const { user } = useSession();
  return <Navigate to={user ? '/' : '/auth'} replace />;
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <SessionProvider>
        <BrowserRouter>
          <Routes>
            <Route element={<AppLayout />}>
              <Route path="/auth" element={<AuthPage />} />
              <Route path="/auth/callback" element={<AuthCallbackPage />} />
              <Route element={<RequireAuthRoute />}>
                <Route path="/" element={<HomePage />} />
                <Route path="/pods" element={<PodsPage />} />
                <Route path="/create-pod" element={<CreatePodPage />} />
                <Route path="/create-event" element={<CreateEventPage />} />
                <Route path="/pod/:id" element={<PodDetailPage />} />
                <Route path="/event/:id" element={<EventDetailPage />} />
                <Route path="/event/edit/:id" element={<EventEditPage />} />
                <Route path="/invites" element={<InvitesPage />} />
                <Route path="/notifications" element={<NotificationsPage />} />
              </Route>
              <Route path="*" element={<FallbackRoute />} />
            </Route>
          </Routes>
        </BrowserRouter>
      </SessionProvider>
    </QueryClientProvider>
  );
}
