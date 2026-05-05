require "test_helper"

class PodsControllerTest < ActionDispatch::IntegrationTest
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

  test "requires authentication for new" do
    get new_pod_path
    assert_redirected_to new_session_path
  end

  test "creates a pod from two of the user's decks" do
    sign_in_as(@user)

    assert_difference -> { @user.pods.count } => 1,
                      -> { Pod.count } => 1,
                      -> { Deck.where(guest_for_pod_id: nil).count } => 0 do
      post pods_path, params: {
        pod_form: {
          name: "Owner-only pod",
          deck_ids: [ @deck_a.id, @deck_b.id ]
        }
      }
    end

    pod = @user.pods.order(:created_at).last
    assert_redirected_to pod_path(pod)
    assert_equal 2, pod.pod_slots.count
    assert_nil pod.guest_decks.first
  end

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

  test "creates a pod with a guest deck from an Archidekt URL" do
    sign_in_as(@user)

    with_archidekt_stub_client(archidekt_sample_json) do
      assert_difference -> { @user.pods.count } => 1 do
        post pods_path, params: {
          pod_form: {
            name: "Archidekt guest pod",
            deck_ids: [ @deck_a.id, @deck_b.id ],
            guest_deck: {
              archidekt_url: "https://archidekt.com/decks/12345/sample"
            }
          }
        }
      end
    end

    pod = @user.pods.order(:created_at).last
    assert_redirected_to pod_path(pod)
    guest_deck = pod.guest_decks.first
    assert guest_deck.present?
    assert_equal "archidekt_url", guest_deck.source_type
    assert_equal "https://archidekt.com/decks/12345", guest_deck.import_metadata["source_url"]
  end

  test "rejects a guest deck that fills more than one source" do
    sign_in_as(@user)

    assert_no_difference -> { Pod.count } do
      post pods_path, params: {
        pod_form: {
          name: "Bad guest",
          deck_ids: [ @deck_a.id, @deck_b.id ],
          guest_deck: {
            decklist: GUEST_DECKLIST,
            archidekt_url: "https://archidekt.com/decks/12345"
          }
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "li", /only one of/i
  end

  test "rejects a guest deck whose decklist cannot be parsed" do
    sign_in_as(@user)

    assert_no_difference -> { Pod.count } do
      post pods_path, params: {
        pod_form: {
          name: "Empty guest",
          deck_ids: [ @deck_a.id, @deck_b.id ],
          guest_deck: {
            decklist: "1 Sol Ring\n1 Command Tower"
          }
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "li", /commander/i
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

  private

    def build_deck(slug)
      deck = @library.build_deck(slug, user: @user)
      deck.save!
      Decks::Analyzer.run(deck)
      deck
    end

    def archidekt_sample_json
      {
        "id" => 12345,
        "name" => "Atraxa Sample",
        "categories" => [
          { "name" => "Commander", "includedInDeck" => true, "isPremier" => true }
        ],
        "cards" => [
          { "quantity" => 1, "categories" => [ "Commander" ],
            "card" => { "oracleCard" => { "name" => "Atraxa, Praetors' Voice" } } },
          { "quantity" => 1, "categories" => [],
            "card" => { "oracleCard" => { "name" => "Sol Ring" } } },
          { "quantity" => 1, "categories" => [],
            "card" => { "oracleCard" => { "name" => "Arcane Signet" } } }
        ]
      }
    end

    def with_archidekt_stub_client(json)
      previous = Decks::Adapters::Archidekt.client_factory
      stub_class = Class.new do
        define_method(:fetch_deck) { |_id| json }
      end
      Decks::Adapters::Archidekt.client_factory = -> { stub_class.new }
      yield
    ensure
      Decks::Adapters::Archidekt.client_factory = previous
    end
end
