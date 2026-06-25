defmodule Job do
  defstruct id: UUID.uuid4(),
            sleep_for: 1,
            status: :pending,
            created_at: DateTime.utc_now(),
            failed_at: nil

  def new(id \\ UUID.uuid4(), sleep_for \\ Enum.random(0..10)) do
    %__MODULE__{
      id: id,
      sleep_for: sleep_for,
      status: :pending
    }
  end

  def update_status(%__MODULE__{} = job, :pending),
    do: %{job | status: :pending}

  def update_status(%__MODULE__{} = job, :running),
    do: %{job | status: :running}

  def update_status(%__MODULE__{} = job, :completed),
    do: %{job | status: :completed}

  def update_status(%__MODULE__{} = job, :failed),
    do: %{job | status: :failed, failed_at: DateTime.utc_now()}
end
