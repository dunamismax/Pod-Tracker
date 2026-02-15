<?php

use App\Livewire\LoginOtpPage;
use App\Livewire\VerifyOtpPage;
use App\Mail\OtpCodeMail;
use App\Models\OtpCode;
use App\Services\OtpAuthService;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;
use Livewire\Livewire;

it('renders otp pages with flux assets', function (): void {
    $this->get('/login')
        ->assertOk()
        ->assertSee('/flux/flux', false);

    $this->get('/verify')
        ->assertOk()
        ->assertSee('/flux/flux', false);
});

it('sends an otp code from the login page', function (): void {
    Mail::fake();

    Livewire::test(LoginOtpPage::class)
        ->set('email', 'PLAYER@example.com')
        ->call('sendCode')
        ->assertRedirect(route('verify', ['email' => 'player@example.com'], false));

    expect(OtpCode::query()->where('email', 'player@example.com')->exists())->toBeTrue();

    Mail::assertSent(OtpCodeMail::class, function (OtpCodeMail $mail): bool {
        return $mail->hasTo('player@example.com');
    });
});

it('verifies a valid otp code and authenticates the user', function (): void {
    Mail::fake();

    $code = app(OtpAuthService::class)->issueCode('player@example.com');

    Livewire::test(VerifyOtpPage::class, ['email' => 'player@example.com'])
        ->set('email', 'player@example.com')
        ->set('code', $code)
        ->call('verify')
        ->assertRedirect(route('dashboard', absolute: false));

    expect(auth()->check())->toBeTrue();
    expect(auth()->user()?->email)->toBe('player@example.com');
    expect(OtpCode::query()->where('email', 'player@example.com')->first()?->consumed_at)->not->toBeNull();
});

it('rejects an invalid otp code', function (): void {
    Mail::fake();

    $code = app(OtpAuthService::class)->issueCode('player@example.com');
    $invalidCode = $code === '000000' ? '000001' : '000000';

    Livewire::test(VerifyOtpPage::class, ['email' => 'player@example.com'])
        ->set('email', 'player@example.com')
        ->set('code', $invalidCode)
        ->call('verify')
        ->assertHasErrors(['code']);

    expect(auth()->check())->toBeFalse();
});

it('throttles repeated otp code requests', function (): void {
    Mail::fake();

    $email = 'throttle-send@example.com';
    $rateLimitKey = 'otp:send:'.$email.'|127.0.0.1';
    RateLimiter::clear($rateLimitKey);

    for ($attempt = 0; $attempt < 5; $attempt++) {
        Livewire::test(LoginOtpPage::class)
            ->set('email', $email)
            ->call('sendCode')
            ->assertRedirect(route('verify', ['email' => $email], false));
    }

    Livewire::test(LoginOtpPage::class)
        ->set('email', $email)
        ->call('sendCode')
        ->assertHasErrors(['email'])
        ->assertSee('Too many code requests.');

    Mail::assertSent(OtpCodeMail::class, 5);
});

it('throttles otp verification attempts', function (): void {
    Mail::fake();

    $email = 'throttle-verify@example.com';
    $rateLimitKey = 'otp:verify:'.$email.'|127.0.0.1';
    RateLimiter::clear($rateLimitKey);

    $code = app(OtpAuthService::class)->issueCode($email);
    $invalidCode = $code === '000000' ? '000001' : '000000';

    for ($attempt = 0; $attempt < 8; $attempt++) {
        Livewire::test(VerifyOtpPage::class, ['email' => $email])
            ->set('email', $email)
            ->set('code', $invalidCode)
            ->call('verify')
            ->assertHasErrors(['code']);
    }

    Livewire::test(VerifyOtpPage::class, ['email' => $email])
        ->set('email', $email)
        ->set('code', $invalidCode)
        ->call('verify')
        ->assertHasErrors(['code'])
        ->assertSee('Too many attempts.');

    expect(auth()->check())->toBeFalse();
});
