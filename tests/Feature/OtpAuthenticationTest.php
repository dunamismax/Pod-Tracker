<?php

use App\Models\User;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Password;

it('renders authentication pages with flux assets', function (): void {
    $this->get('/login')
        ->assertOk()
        ->assertSee('/flux/flux', false)
        ->assertSee('class="h-full dark"', false)
        ->assertSee('name="remember"', false);

    $this->get('/register')
        ->assertOk()
        ->assertSee('/flux/flux', false)
        ->assertSee('class="h-full dark"', false);

    $this->get('/forgot-password')
        ->assertOk()
        ->assertSee('/flux/flux', false)
        ->assertSee('class="h-full dark"', false);
});

it('registers a user with the built-in auth flow', function (): void {
    $response = $this->post('/register', [
        'name' => 'New Player',
        'email' => 'player@example.com',
        'password' => 'password',
        'password_confirmation' => 'password',
    ]);

    $response->assertRedirect(route('dashboard', absolute: false));

    $this->assertAuthenticated();
    expect(User::query()->where('email', 'player@example.com')->exists())->toBeTrue();
});

it('authenticates a user with valid credentials', function (): void {
    $user = User::factory()->create([
        'email' => 'player@example.com',
        'password' => 'password',
    ]);

    $response = $this->post('/login', [
        'email' => 'player@example.com',
        'password' => 'password',
    ]);

    $response->assertRedirect(route('dashboard', absolute: false));

    $this->assertAuthenticatedAs($user);
});

it('rejects invalid credentials', function (): void {
    User::factory()->create([
        'email' => 'player@example.com',
        'password' => 'password',
    ]);

    $response = $this->from('/login')->post('/login', [
        'email' => 'player@example.com',
        'password' => 'wrong-password',
    ]);

    $response->assertRedirect('/login');
    $response->assertSessionHasErrors('email');
    $this->assertGuest();
});

it('logs out an authenticated user', function (): void {
    $user = User::factory()->create();

    $response = $this->actingAs($user)->post('/logout');

    $response->assertRedirect('/');
    $this->assertGuest();
});

it('sends a password reset link', function (): void {
    Notification::fake();

    $user = User::factory()->create([
        'email' => 'player@example.com',
    ]);

    $response = $this->post('/forgot-password', [
        'email' => 'player@example.com',
    ]);

    $response->assertSessionHas('status');

    Notification::assertSentTo($user, ResetPassword::class);
});

it('resets the password with a valid token', function (): void {
    $user = User::factory()->create([
        'email' => 'player@example.com',
        'password' => 'password',
    ]);

    $token = Password::broker()->createToken($user);

    $response = $this->post('/reset-password', [
        'token' => $token,
        'email' => 'player@example.com',
        'password' => 'new-password',
        'password_confirmation' => 'new-password',
    ]);

    $response
        ->assertRedirect(route('login', absolute: false))
        ->assertSessionHas('status');

    $this->post('/login', [
        'email' => 'player@example.com',
        'password' => 'new-password',
    ])->assertRedirect(route('dashboard', absolute: false));

    $this->assertAuthenticated();
});
