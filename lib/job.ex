defmodule Job do
  @enforce_keys [:id, :work, :created_at]
  defstruct id: nil,
            work: nil,
            status: :pending,
            created_at: nil,
            ended_at: nil,
            failed_at: nil,
            result: nil

  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, UUID.uuid4()),
      work: Keyword.fetch!(opts, :work),
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
