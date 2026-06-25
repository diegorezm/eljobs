defmodule Job do
  defstruct id: nil,
            sleep_for: 1,
            status: :pending,
            created_at: nil,
            failed_at: nil

  def new(id \\ UUID.uuid4(), sleep_for \\ Enum.random(0..10)) do
    %__MODULE__{
      id: id,
      sleep_for: sleep_for,
      status: :pending,
      created_at: DateTime.utc_now()
    }
  end

  def update_status(job, status)
      when status in [:pending, :running, :completed] do
    %{job | status: status}
  end

  def update_status(job, :failed) do
    %{job | status: :failed, failed_at: DateTime.utc_now()}
  end
end
