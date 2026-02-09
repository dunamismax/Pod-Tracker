import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';

import { useProfile, useUpsertProfile } from '@/features/profiles/profiles-queries';
import { supabase } from '@/lib/supabase';
import { useSession } from '@/web/session-context';

export function AuthPage() {
  const navigate = useNavigate();
  const { user, isLoading } = useSession();
  const profileQuery = useProfile(user?.id);
  const upsertProfile = useUpsertProfile();

  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [status, setStatus] = useState<string | null>(null);
  const [isSendingCode, setIsSendingCode] = useState(false);
  const [isVerifyingCode, setIsVerifyingCode] = useState(false);
  const [codeSentToEmail, setCodeSentToEmail] = useState<string | null>(null);
  const [lastCodeSentAt, setLastCodeSentAt] = useState<number | null>(null);
  const [cooldownSeconds, setCooldownSeconds] = useState(0);
  const [profileStatus, setProfileStatus] = useState<string | null>(null);

  const [displayName, setDisplayName] = useState('');
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [phone, setPhone] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [contactHandle, setContactHandle] = useState('');
  const [contactNotes, setContactNotes] = useState('');

  const emailError = email.length > 0 && !email.includes('@');
  const codeError = code.length > 0 && code.trim().length < 6;
  const firstNameError = firstName.trim().length === 0;
  const lastNameError = lastName.trim().length === 0;
  const contactEmailError = contactEmail.length > 0 && !contactEmail.includes('@');

  useEffect(() => {
    if (!profileQuery.data) return;
    setDisplayName(profileQuery.data.display_name ?? '');
    setFirstName(profileQuery.data.first_name ?? '');
    setLastName(profileQuery.data.last_name ?? '');
    setPhone(profileQuery.data.phone ?? '');
    setContactEmail(profileQuery.data.contact_email ?? '');
    setContactHandle(profileQuery.data.contact_handle ?? '');
    setContactNotes(profileQuery.data.contact_notes ?? '');
  }, [profileQuery.data]);

  useEffect(() => {
    if (!lastCodeSentAt) return;
    const tick = () => {
      const remainingMs = 60_000 - (Date.now() - lastCodeSentAt);
      const remaining = Math.max(0, Math.ceil(remainingMs / 1000));
      setCooldownSeconds(remaining);
      if (remaining === 0) setLastCodeSentAt(null);
    };
    tick();
    const timer = window.setInterval(tick, 1000);
    return () => window.clearInterval(timer);
  }, [lastCodeSentAt]);

  const handleSendCode = async () => {
    if (!email || emailError || lastCodeSentAt) return;
    const normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail) return;

    setIsSendingCode(true);
    setStatus(null);

    const { error } = await supabase.auth.signInWithOtp({
      email: normalizedEmail,
      options: { shouldCreateUser: true },
    });

    if (error) {
      setStatus(error.status === 429 ? 'Too many requests. Wait a minute and try again.' : error.message);
    } else {
      setCodeSentToEmail(normalizedEmail);
      setStatus(`Code sent to ${normalizedEmail}. Enter it below to sign in.`);
      setLastCodeSentAt(Date.now());
    }

    setIsSendingCode(false);
  };

  const handleVerifyCode = async () => {
    const normalizedEmail = codeSentToEmail ?? email.trim().toLowerCase();
    if (!normalizedEmail || !code.trim() || emailError || codeError) return;

    setIsVerifyingCode(true);
    setStatus(null);

    const { error } = await supabase.auth.verifyOtp({
      email: normalizedEmail,
      token: code.trim(),
      type: 'email',
    });

    if (error) {
      setStatus(error.message);
    } else {
      setCode('');
      setStatus('Sign-in complete. Redirecting...');
      navigate('/');
    }

    setIsVerifyingCode(false);
  };

  const handleSignOut = async () => {
    setIsSendingCode(true);
    setStatus(null);
    const { error } = await supabase.auth.signOut();
    if (error) {
      setStatus(error.message);
    }
    setIsSendingCode(false);
  };

  const handleSaveProfile = async () => {
    if (!user || firstNameError || lastNameError || contactEmailError) return;
    setProfileStatus(null);
    try {
      await upsertProfile.mutateAsync({
        id: user.id,
        email: user.email ?? null,
        display_name: displayName.trim() ? displayName.trim() : null,
        first_name: firstName.trim(),
        last_name: lastName.trim(),
        phone: phone.trim() ? phone.trim() : null,
        contact_email: contactEmail.trim() ? contactEmail.trim() : null,
        contact_handle: contactHandle.trim() ? contactHandle.trim() : null,
        contact_notes: contactNotes.trim() ? contactNotes.trim() : null,
      });
      setProfileStatus('Profile saved.');
    } catch (error) {
      setProfileStatus(error instanceof Error ? error.message : 'Unable to save profile.');
    }
  };

  return (
    <div className="stack">
      <section className="panel">
        <h2>Sign in</h2>
        <p className="muted">Email + one-time code.</p>
        <label className="field">
          Email
          <input
            className="input"
            onChange={(event) => setEmail(event.target.value)}
            type="email"
            value={email}
          />
        </label>
        {emailError ? <p className="error">Enter a valid email address.</p> : null}
        <button
          className="btn btn-primary"
          disabled={isSendingCode || isVerifyingCode || isLoading || !email || emailError || Boolean(lastCodeSentAt)}
          onClick={handleSendCode}
          type="button">
          {cooldownSeconds > 0 ? `Try again in ${cooldownSeconds}s` : 'Send code'}
        </button>

        <label className="field">
          One-time code
          <input
            className="input"
            inputMode="numeric"
            onChange={(event) => setCode(event.target.value)}
            value={code}
          />
        </label>
        {codeError ? <p className="error">Enter the full code from your email.</p> : null}
        <button
          className="btn btn-outline"
          disabled={isSendingCode || isVerifyingCode || !email || emailError || !code.trim() || codeError}
          onClick={handleVerifyCode}
          type="button">
          {isVerifyingCode ? 'Verifying...' : 'Verify code and sign in'}
        </button>
        {status ? <p className="muted">{status}</p> : null}
      </section>

      <section className="panel">
        <h3>Session</h3>
        {isLoading ? (
          <p className="muted">Checking session...</p>
        ) : user ? (
          <>
            <p className="muted">Signed in as {user.email ?? 'Unknown email'}.</p>
            <button className="btn btn-outline" onClick={handleSignOut} type="button">
              Sign out
            </button>
          </>
        ) : (
          <p className="muted">No active session.</p>
        )}
      </section>

      {user ? (
        <section className="panel">
          <h3>Your profile</h3>
          <div className="grid">
            <label className="field">
              Display name
              <input
                className="input"
                onChange={(event) => setDisplayName(event.target.value)}
                value={displayName}
              />
            </label>
            <label className="field">
              First name
              <input
                className="input"
                onChange={(event) => setFirstName(event.target.value)}
                value={firstName}
              />
            </label>
            <label className="field">
              Last name
              <input
                className="input"
                onChange={(event) => setLastName(event.target.value)}
                value={lastName}
              />
            </label>
            <label className="field">
              Phone
              <input className="input" onChange={(event) => setPhone(event.target.value)} value={phone} />
            </label>
            <label className="field">
              Contact email
              <input
                className="input"
                onChange={(event) => setContactEmail(event.target.value)}
                type="email"
                value={contactEmail}
              />
            </label>
            <label className="field">
              Contact handle
              <input
                className="input"
                onChange={(event) => setContactHandle(event.target.value)}
                value={contactHandle}
              />
            </label>
            <label className="field full">
              Notes
              <textarea
                className="input"
                onChange={(event) => setContactNotes(event.target.value)}
                rows={4}
                value={contactNotes}
              />
            </label>
          </div>
          {firstNameError ? <p className="error">First name is required.</p> : null}
          {lastNameError ? <p className="error">Last name is required.</p> : null}
          {contactEmailError ? <p className="error">Enter a valid contact email.</p> : null}
          <button
            className="btn btn-primary"
            disabled={
              profileQuery.isLoading ||
              upsertProfile.isPending ||
              firstNameError ||
              lastNameError ||
              contactEmailError
            }
            onClick={handleSaveProfile}
            type="button">
            Save profile
          </button>
          {profileStatus ? <p className="muted">{profileStatus}</p> : null}
        </section>
      ) : null}
    </div>
  );
}
