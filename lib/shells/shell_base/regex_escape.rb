module Shells
  class ShellBase
    private

    def regex_escape(text)
      text
          .gsub('\\', '\\\\')
          .gsub('[', '\\[')
          .gsub(']', '\\]')
          .gsub('(', '\\(')
          .gsub(')', '\\)')
          .gsub('.', '\\.')
          .gsub('*', '\\*')
          .gsub('+', '\\+')
          .gsub('?', '\\?')
          .gsub('{', '\\{')
          .gsub('}', '\\}')
          .gsub('$', '\\$')
          .gsub('^', '\\^')
    end

  end
end