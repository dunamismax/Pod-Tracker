<?php

use App\Livewire\DashboardPage;
use App\Models\Event;
use App\Models\Pod;
use App\Models\PodMember;
use App\Models\User;
use Illuminate\Support\Carbon;
use Livewire\Livewire;

it('creates a pod from the dashboard page', function (): void {
    $user = User::factory()->create([
        'password' => null,
    ]);

    $this->actingAs($user);

    Livewire::test(DashboardPage::class)
        ->set('name', 'Friday Pod')
        ->set('description', 'Casual commander table')
        ->call('createPod')
        ->assertHasNoErrors();

    expect(Pod::query()->where('name', 'Friday Pod')->where('owner_id', $user->id)->exists())->toBeTrue();
    expect(PodMember::query()->where('user_id', $user->id)->where('role', 'owner')->exists())->toBeTrue();
});

it('shows upcoming events for pods the user belongs to', function (): void {
    $user = User::factory()->create([
        'password' => null,
    ]);

    $pod = Pod::query()->create([
        'name' => 'Guild Pod',
        'description' => null,
        'owner_id' => $user->id,
    ]);

    PodMember::query()->create([
        'pod_id' => $pod->id,
        'user_id' => $user->id,
        'role' => 'owner',
        'joined_at' => Carbon::now(),
    ]);

    Event::query()->create([
        'pod_id' => $pod->id,
        'title' => 'Commander Night',
        'description' => null,
        'location' => 'LGS',
        'scheduled_for' => Carbon::now()->addHours(3),
        'created_by' => $user->id,
    ]);

    $this->actingAs($user)
        ->get('/dashboard')
        ->assertOk()
        ->assertSee('class="h-full dark"', false)
        ->assertSee('Magic Pod Dashboard')
        ->assertSee('Commander Night')
        ->assertSee('Guild Pod');
});
