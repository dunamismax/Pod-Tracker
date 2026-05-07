require "test_helper"

class PodsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    CommanderFormat::CardTagImporter.new.import!
    @user = users(:one)
    @library = Decks::FixtureLibrary.new
    @deck_a = build_deck("krenko_goblin_tribal")
    @deck_b = build_deck("mono_green_omnath_stompy")
  end

  GUEST_DECKLIST = <<~TXT.freeze
    Commander
    1 Atraxa, Praetors' Voice

    Mainboard
    1 Sol Ring
    1 Arcane Signet
    1 Command Tower
  TXT

  test "creates a pod with a pasted guest deck" do
    sign_in_as(@user)

    assert_difference -> { @user.pods.count } => 1,
                      -> { Deck.count } => 1 do
      post pods_path, params: {
        pod_form: {
          name: "Mixed pod with guest",
          deck_ids: [ @deck_a.id, @deck_b.id ],
          guest_deck: {
            name: "Atraxa Brew",
            label: "Mara",
            decklist: GUEST_DECKLIST
          }
        }
      }
    end

    pod = @user.pods.order(:created_at).last
    assert_redirected_to pod_path(pod)
    assert_equal 3, pod.pod_slots.count

    guest_slot = pod.pod_slots.order(:position).last
    assert_equal "Mara", guest_slot.label
    guest_deck = guest_slot.deck
    assert_nil guest_deck.user_id
    assert_equal pod.id, guest_deck.guest_for_pod_id
    assert guest_deck.guest?
    assert_equal [ "Atraxa, Praetors' Voice" ], guest_deck.commander_names
    assert_equal "Atraxa Brew", guest_deck.name
    assert_equal "pasted_text", guest_deck.source_type

    audit = AuditEvent.where(event_name: "pod.analyzed").order(:created_at).last
    assert_equal pod.id, audit.auditable_id
    assert_equal "pasted_text", audit.metadata["guest_deck_source"]
  end

  test "destroying a pod removes its guest decks" do
    sign_in_as(@user)

    post pods_path, params: {
      pod_form: {
        name: "Disposable pod",
        deck_ids: [ @deck_a.id, @deck_b.id ],
        guest_deck: { decklist: GUEST_DECKLIST }
      }
    }
    pod = @user.pods.order(:created_at).last
    assert_equal 1, pod.guest_decks.count

    assert_difference -> { Pod.count } => -1,
                      -> { Deck.where(guest_for_pod_id: pod.id).count } => -1 do
      delete pod_path(pod)
    end
    assert_redirected_to pods_path
  end

  test "queues an AI pod evaluation from the show page action" do
    sign_in_as(@user)
    connect_codex_account!
    pod = Pod.create!(user: @user, name: "AI pod", format: "commander", status: "draft")
    pod.pod_slots.create!(deck: @deck_a, position: 1)
    pod.pod_slots.create!(deck: @deck_b, position: 2)
    Pods::Analyzer.run(pod, user: @user)
    clear_enqueued_jobs

    assert_difference -> { pod.analysis_runs.where(kind: "ai").count }, 1 do
      assert_enqueued_with(job: CodexEvaluationJob) do
        post pod_ai_evaluation_path(pod)
      end
    end

    assert_redirected_to pod_path(pod)
    assert_equal "queued", pod.latest_ai_run.status
  ensure
    clear_enqueued_jobs
  end

  private

    def build_deck(slug)
      deck = @library.build_deck(slug, user: @user)
      deck.save!
      Decks::Analyzer.run(deck)
      deck
    end

    def connect_codex_account!
      @user.codex_account&.destroy
      @user.create_codex_account!(
        auth_mode: Codex::AccountConnections::BROWSER_AUTH_MODE,
        status: "connected",
        encrypted_credential_payload: "opaque",
        rate_limit_snapshot: { "primary" => { "used" => 1, "limit" => 100 } },
        connected_at: Time.current
      )
    end
end
