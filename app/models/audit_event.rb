class AuditEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :auditable, polymorphic: true, optional: true

  validates :event_name, presence: true
  validates :occurred_at, presence: true

  before_validation :set_default_occurred_at

  private

  def set_default_occurred_at
    self.occurred_at ||= Time.current
  end
end
