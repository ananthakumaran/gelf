import ExProf.Macro
require Logger

profile do
  Enum.each(Range.new(0, 10000), fn _ ->
    Logger.info "asdfa sdfad fasdf asdfa dfasd fasdf asdfas dfasd fasdfa sdfasdafdfa"
  end)
end
