module Docbookrx
class DocbookVisitor
  # transfer node type constants from Nokogiri
  ::Nokogiri::XML::Node.constants.grep(/_NODE$/).each do |sym|
    const_set sym, (::Nokogiri::XML::Node.const_get sym)
  end

  IndentationRx = /^[[:blank:]]+/
  LeadingSpaceRx = /\A\s/
  LeadingEndlinesRx = /\A\n+/
  TrailingEndlinesRx = /\n+\z/
  FirstLineIndentRx = /\A[[:blank:]]*/
  WrappedIndentRx = /\n[[:blank:]]*/

  EOL = "\n"

  ENTITY_TABLE = {
     169 => '(C)',
     174 => '(R)',
    8201 => ' ', # thin space
    8212 => '--',
    8216 => '\'`',
    8217 => '`\'',
    8220 => '"`',
    8221 => '`"',
    8230 => '...',
    8482 => '(TM)',
    8592 => '<-',
    8594 => '->',
    8656 => '<=',
    8658 => '=>'
  }

  REPLACEMENT_TABLE = {
    ':: ' => '{two-colons} '
  }

  PARA_TAG_NAMES = ['para', 'simpara']

  #COMPLEX_PARA_TAG_NAMES = ['formalpara', 'para']

  ADMONITION_NAMES = ['note', 'tip', 'warning', 'caution', 'important']

  NORMAL_SECTION_NAMES = ['section', 'simplesect', 'sect1', 'sect2', 'sect3', 'sect4', 'sect5']

  SPECIAL_SECTION_NAMES = ['abstract', 'appendix', 'bibliography', 'glossary', 'preface']

  DOCUMENT_NAMES = ['article', 'book']

  SECTION_NAMES = DOCUMENT_NAMES + ['chapter', 'part'] + NORMAL_SECTION_NAMES + SPECIAL_SECTION_NAMES

  ANONYMOUS_LITERAL_NAMES = ['code', 'command', 'computeroutput', 'database', 'function', 'literal', 'tag', 'userinput']

  NAMED_LITERAL_NAMES = ['application', 'classname', 'constant', 'envar', 'exceptionname', 'interfacename', 'methodname', 'option', 'parameter', 'property', 'replaceable', 'type', 'varname']

  LITERAL_NAMES = ANONYMOUS_LITERAL_NAMES + NAMED_LITERAL_NAMES

  KEYWORD_NAMES = ['package', 'firstterm', 'citetitle']

  PATH_NAMES = ['directory', 'filename', 'systemitem']

  UI_NAMES = ['guibutton', 'guilabel', 'menuchoice', 'guimenu', 'keycap']

  attr_reader :lines

  def initialize opts = {}
    @lines = []
    @level = 1
    @skip = {}
    @requires_index = false
    @list_index = 0
    @continuation = false
    @adjoin_next = false
    # QUESTION why not handle idprefix and idseparator as attributes (delete on read)?
    @idprefix = opts[:idprefix] || '_'
    @idseparator = opts[:idseparator] || '_'
    @normalize_ids = opts.fetch :normalize_ids, true
    @compat_mode = opts[:compat_mode]
    @attributes = opts[:attributes] || {}
    @runin_admonition_label = opts.fetch :runin_admonition_label, true
    @sentence_per_line = opts.fetch :sentence_per_line, true
    @preserve_line_wrap = if @sentence_per_line
      false
    else
      opts.fetch :preserve_line_wrap, true
    end
    @delimit_source = opts.fetch :delimit_source, true
  end

  ## Traversal methods

  # Main processor loop
  def visit node
    return if node.type == COMMENT_NODE
    return if node.instance_variable_get :@skip

    before_traverse if (at_root = (node == node.document.root)) && (respond_to? :before_traverse)

    name = node.name
    visit_method_name = case node.type
    when PI_NODE
      :visit_pi
    when ENTITY_REF_NODE
      :visit_entity_ref
    else
      if ADMONITION_NAMES.include? name
        :process_admonition
      elsif LITERAL_NAMES.include? name
        :process_literal
      elsif KEYWORD_NAMES.include? name
        :process_keyword
      elsif PATH_NAMES.include? name
        :process_path
      elsif UI_NAMES.include? name
        :process_ui
      elsif NORMAL_SECTION_NAMES.include? name
        :process_section
      elsif SPECIAL_SECTION_NAMES.include? name
        :process_special_section
      else
        %(visit_#{name}).to_sym
      end
    end

    result = if respond_to? visit_method_name
      send visit_method_name, node
    elsif respond_to? :default_visit
      send :default_visit, node
    end

    traverse_children node if result == true
    after_traverse if at_root && (respond_to? :after_traverse)
  end

  def traverse_children node, opts = {}
    (opts[:using_elements] ? node.elements : node.children).each do |child|
      child.accept self
    end
  end
  alias :proceed :traverse_children

  ## Text extraction and processing methods

  def text node, unsub = true
    if node
      if node.is_a? ::Nokogiri::XML::Node
        unsub ? reverse_subs(node.text) : node.text
      elsif node.is_a? ::Nokogiri::XML::NodeSet && (first = node.first)
        unsub ? reverse_subs(first.text) : first.text
      else
        nil
      end
    else
      nil
    end
  end

  def text_at_css node, css, unsub = true
    text (node.at_css css, unsub)
  end

  def format_text node
    if node && (node.is_a? ::Nokogiri::XML::NodeSet)
      node = node.first
    end

    if node.is_a? ::Nokogiri::XML::Node
      append_blank_line
      proceed node
      @lines.pop
    else
      nil
    end
  end

  def format_text_at_css node, css
    format_text (node.at_css css)
  end

  def entity number
    [number].pack 'U*'
  end

  # Replaces XML entities, and other encoded forms that AsciiDoc automatically
  # applies, with their plain-text equivalents.
  #
  # This method effectively undoes the inline substitutions that AsciiDoc performs.
  #
  # str - The String to processes
  #
  # Examples
  #
  #   reverse_subs "&#169; Acme, Inc."
  #   # => "(C) Acme, Inc."
  #
  # Returns The processed String
  def reverse_subs str
    ENTITY_TABLE.each do |num, text|
      str = str.gsub((entity num), text)
    end
    REPLACEMENT_TABLE.each do |original, replacement|
      str = str.gsub original, replacement
    end
    str
  end

  ## Writer methods

  def append_line line = '', unsub = false
    line = reverse_subs line if !line.empty? && unsub
    @lines << line
  end

  def append_blank_line
    if @continuation
      @continuation = false
    elsif @adjoin_next
      @adjoin_next = false
    else
      @lines << ''
    end
  end
  alias :start_new_line :append_blank_line

  def append_block_title node, prefix = nil
    if (title_node = (node.at_css '> title') || (node.at_css '> info > title'))
      title = format_text title_node
      leading_char = '.'
      # special case for <itemizedlist role="see-also-list"><title>:
      # omit the prefix '.' as we want simple text on a bullet, not a heading
      if node.parent.name == 'itemizedlist' && ((node.attr 'role') == 'see-also-list')
        leading_char = nil
      end
      append_line %(#{leading_char}#{prefix}#{unwrap_text title})
      @adjoin_next = true
      true
    else
      false
    end
  end

  def append_block_role node
    if (role = node.attr('role'))
      append_line %([.#{role}])
      #@adjoin_next = true
      true
    else
      false
    end
  end

  def append_text text, unsub = false
    text = reverse_subs text if unsub
    @lines[-1] = %(#{@lines[-1]}#{text})
  end

  ## Lifecycle callbacks

  #def before_traverse
  #end

  def after_traverse
    if @requires_index
      append_blank_line
      append_line 'ifdef::backend-docbook[]'
      append_line '[index]'
      append_line '== Index'
      append_line '// Generated automatically by the DocBook toolchain.'
      append_line 'endif::backend-docbook[]'
    end
  end

  ## Node visitor callbacks

 def default_visit node
    warn %(No visitor defined for <#{node.name}>! Skipping.)
    false
  end

  # pass thru XML entities unchanged, eg., for &rarr;
  def visit_entity_ref node
    append_text %(#{node})
    false
  end

  def ignore node
    false
  end
  # Skip title and subtitle as they're always handled by the parent visitor
  alias :visit_title :ignore
  alias :visit_subtitle :ignore

  alias :visit_toc :ignore

  ### Document node (article | book | chapter) & header node (articleinfo | bookinfo | info) visitors

  def visit_book node
    process_doc node
  end

  def visit_article node
    process_doc node
  end

  def visit_info node
    process_info node if DOCUMENT_NAMES.include? node.parent.name
  end
  alias :visit_bookinfo :visit_info
  alias :visit_articleinfo :visit_info

  def visit_chapter node
    # treat document with <chapter> root element as books
    if node == node.document.root
      @adjoin_next = true
      process_section node do
        append_line ':compat-mode:' if @compat_mode
        append_line ':doctype: book'
        append_line ':sectnums:'
        append_line ':toc: left'
        append_line ':icons: font'
        append_line ':experimental:'
        append_line %(:idprefix: #{@idprefix}).rstrip unless @idprefix == '_'
        append_line %(:idseparator: #{@idseparator}).rstrip unless @idseparator == '_'
        append_line %(:sourcedir: .) unless @attributes.key? 'sourcedir'
        @attributes.each do |name, val|
          append_line %(:#{name}: #{val}).rstrip
        end
      end
    else
      process_section node
    end
  end

  def process_doc node
    @level += 1
    proceed node, :using_elements => true
    @level -= 1
    false
  end

  def process_info node
    title = text_at_css node, '> title'
    append_line %(= #{title})
    authors = []
    (node.css 'author').each do |author_node|
      # FIXME need to detect DocBook 4.5 vs 5.0 to handle names properly
      author = if (personname_node = (author_node.at_css 'personname'))
        text personname_node
      else
        [(text_at_css author_node, 'firstname'), (text_at_css author_node, 'surname')].compact * ' '
      end
      if (email_node = (author_node.at_css 'email'))
        author = %(#{author} <#{text email_node}>)
      end
      authors << author unless author.empty?
    end
    append_line (authors * '; ') unless authors.empty?
    date_line = nil
    if (revnumber_node = node.at_css('revhistory revnumber', 'releaseinfo'))
      date_line = %(v#{revnumber_node.text}, ) 
    end
    if (date_node = node.at_css('> date', '> pubdate'))
      append_line %(#{date_line}#{date_node.text})
    end
    if node.name == 'bookinfo' || node.parent.name == 'book' || node.parent.name == 'chapter'
      append_line ':compat-mode:' if @compat_mode
      append_line ':doctype: book'
      append_line ':sectnums:'
      append_line ':toc: left'
      append_line ':icons: font'
      append_line ':experimental:'
    end
    append_line %(:idprefix: #{@idprefix}).rstrip unless @idprefix == '_'
    append_line %(:idseparator: #{@idseparator}).rstrip unless @idseparator == '_'
    @attributes.each do |name, val|
      append_line %(:#{name}: #{val}).rstrip
    end
    false
  end

  # Very rough first pass at processing xi:include
  def visit_include node
    # QUESTION should we reuse this instance to traverse the new tree?
    include_infile = node.attr 'href'
    include_outfile = include_infile.sub '.xml', '.adoc'
    if ::File.readable? include_infile
      doc = ::Nokogiri::XML::Document.parse(::File.read include_infile)
      # TODO pass in options that were passed to this visitor
      visitor = self.class.new
      doc.root.accept visitor
      result = visitor.lines
      result.shift while result.size > 0 && result.first.empty?
      ::File.open(include_outfile, 'w') {|f| f.write(visitor.lines * EOL) }
    else
      warn %(Include file not readable: #{include_infile})
    end
    append_blank_line
    # TODO make leveloffset more context-aware
    append_line %(:leveloffset: #{@level - 1}) if @level > 1
    append_line %(include::#{include_outfile}[])
    append_line %(:leveloffset: 0) if @level > 1
    false
  end

  ### Section node visitors

  def visit_bridgehead node
    level = node.attr('renderas').sub('sect', '').to_i + 1
    append_blank_line
    append_line '[float]'
    title = format_text node
    if (id = (resolve_id node, normalize: @normalize_ids)) && id != (generate_id title)
      append_line %([[#{id}]])
    end
    append_line %(#{'=' * level} #{unwrap_text title})
    false
  end

  def process_special_section node
    process_section node, node.name
  end

  def process_section node, special = nil
    append_blank_line
    if special
      append_line ':sectnums!:'
      append_blank_line
      append_line %([#{special}])
    end
    title = if (title_node = (node.at_css '> title') || (node.at_css '> info > title'))
      if (subtitle_node = (node.at_css '> subtitle') || (node.at_css '> info > subtitle'))
        title_node.inner_html += %(: #{subtitle_node.inner_html})
      end
      format_text title_node
    else
      warn %(No title found for section node: #{node})
      'Unknown Title!'
    end
    if (id = (resolve_id node, normalize: @normalize_ids)) && id != (generate_id title)
      append_line %([[#{id}]])
    end
    append_line %(#{'=' * @level} #{unwrap_text title})
    yield if block_given?
    if (abstract_node = (node.at_css '> info > abstract'))
      append_line
      append_line '[abstract]'
      append_line '--'
      abstract_node.elements.each do |el|
        append_line
        proceed el
        append_line
      end
      append_text '--'
    end
    @level += 1
    proceed node, :using_elements => true
    @level -= 1
    if special
      append_blank_line
      append_line ':sectnums:'
    end
    false
  end

  def generate_id title
    sep = @idseparator
    pre = @idprefix
    # FIXME move regexp to constant
    illegal_sectid_chars = /&(?:[[:alpha:]]+|#[[:digit:]]+|#x[[:alnum:]]+);|\W+?/
    id = %(#{pre}#{title.downcase.gsub(illegal_sectid_chars, sep).tr_s(sep, sep).chomp(sep)})
    if pre.empty? && id.start_with?(sep)
      id = id[1..-1]
      id = id[1..-1] while id.start_with?(sep)
    end
    id
  end

  def resolve_id node, opts = {}
    if (id = node['id'] || node['xml:id'])
      opts[:normalize] ? (normalize_id id) : id
    else
      nil
    end
  end

  # Lowercase id and replace underscores or hyphens with the @idseparator
  # TODO ensure id adheres to @idprefix
  def normalize_id id
    if id
      normalized_id = id.downcase.tr('_-', @idseparator)
      normalized_id = %(#{@idprefix}#{normalized_id}) if @idprefix && !(normalized_id.start_with? @idprefix)
      normalized_id
    else
      nil
    end
  end

  ### Block node visitors

  def visit_formalpara node
    append_blank_line
    append_block_title node
    true
  end

  def visit_para node
    append_blank_line
    append_block_role node
    append_blank_line
    true
  end

  def visit_simpara node
    append_blank_line
    append_block_role node
    append_blank_line
    true
  end

  def process_admonition node
    name = node.name
    label = name.upcase
    elements = node.elements
    append_blank_line
    append_block_title node
    if elements.size == 1 && (PARA_TAG_NAMES.include? (child = elements.first).name)
      if @runin_admonition_label
        append_line %(#{label}: #{format_text child})
      else
        append_line %([#{label}])
        append_line (format_text child)
      end
    else
      append_line %([#{label}])
      append_line '===='
      @adjoin_next = true
      proceed node
      @adjoin_next = false
      append_line '===='
    end
    false
  end

  def visit_itemizedlist node
    append_blank_line
    append_block_title node
    true
  end

  def visit_procedure node
    append_blank_line
    append_block_title node, 'Procedure: '
    visit_orderedlist node
  end

  def visit_substeps node
    visit_orderedlist node
  end

  def visit_stepalternatives node
    visit_orderedlist node
  end

 def visit_orderedlist node
    @list_index = 1
    append_blank_line
    # TODO no title?
    if (numeration = (node.attr 'numeration')) && numeration != 'arabic'
      append_line %([#{numeration}])
    end
    true
  end

  def visit_variablelist node
    append_blank_line
    append_block_title node
    @lines.pop if @lines[-1].empty?
    true
  end

  def visit_step node
    visit_listitem node
  end

  # FIXME this method needs cleanup, remove hardcoded logic!
  def visit_listitem node
    elements = node.elements.to_a
    item_text = if elements.size > 0
      format_text elements.shift
    else
      format_text node
    end
    
    # do we want variable depths of bullets?
    depth = (node.ancestors.length - 4)
    # or static bullet depths
    depth = 1

    marker = (node.parent.name == 'orderedlist' || node.parent.name == 'procedure' ? '.' * depth : 
      (node.parent.name == 'stepalternatives' ? 'a.' : '*' * depth))
    placed_bullet = false
    item_text.split(EOL).each_with_index do |line, i|
      line = line.gsub IndentationRx, ''
      if line.length > 0
        if line == '====' # ???
          append_line %(#{line})
        elsif !placed_bullet
          append_line %(#{marker} #{line})
          placed_bullet = true
        else
          append_line %(  #{line})
        end
      end
    end

    unless elements.empty?
      elements.each_with_index do |child, i|
        unless i == 0 && child.name == 'literallayout'
          append_line '+'
          @continuation = true
        end
        child.accept self
      end
      append_blank_line
    end
    false
  end

  def visit_varlistentry node
    # FIXME adds an extra blank line before first item
    #append_blank_line unless (previous = node.previous_element) && previous.name == 'title'
    append_blank_line
    append_line %(#{format_text(node.at_css node, '> term')}::)
    item_text = format_text(node.at_css node, '> listitem > para', '> listitem > simpara')
    if item_text
      item_text.split(EOL).each do |line|
        append_line %(  #{line})
      end
    end

    # support listitem figures in a listentry
    # FIXME we should be supporting arbitrary complex content!
    if node.at_css('listitem figure')
      # warn %(#{node.at_css('listitem figure')})
      visit_figure node.at_css('listitem figure')
    end

    # FIXME this doesn't catch complex children
    false
  end

  def visit_glossentry node
    append_blank_line
    if !(previous = node.previous_element) || previous.name != 'glossentry'
      append_line '[glossary]'
    end
    true
  end

  def visit_glossterm node
    append_line %(#{format_text node}::)
    false
  end

  def visit_glossdef node
    append_line %(  #{text node.elements.first})
    false
  end

  def visit_citation node
    append_text %(<<#{node.text}>>)
  end

  def visit_bibliodiv node
    append_blank_line
    append_line '[bibliography]'
    true
  end

  def visit_bibliomisc node
    true
  end

  def visit_bibliomixed node
    append_blank_line
    proceed node
    append_line @lines.pop.sub(/^\[(.*?)\]/, '* [[[\\1]]]')
    false
  end

  def visit_literallayout node
    append_blank_line
    source_lines = node.text.rstrip.split EOL
    if (source_lines.detect{|line| line.rstrip.empty?})
      append_line '....'
      append_line node.text.rstrip
      append_line '....'
    else
      source_lines.each do |line|
        append_line %(  #{line})
      end
    end
    false
  end

  def visit_screen node
    append_blank_line unless node.parent.name == 'para'
    source_lines = node.text.rstrip.split EOL
    if source_lines.detect {|line| line.match(/^-{4,}/) }
      append_line '[listing]'
      append_line '....'
      append_line node.text.rstrip
      append_line '....'
    else
      append_line '----'
      append_line node.text.rstrip
      append_line '----'
    end
    false
  end

  def visit_programlisting node
    language = node.attr('language') || node.attr('role') || @attributes['source-language']
    language = %(,#{language.downcase}) if language
    linenums = node.attr('linenumbering') == 'numbered'
    append_blank_line unless node.parent.name == 'para'
    append_line %([source#{language}#{linenums ? ',linenums' : nil}])
    if (first_element = node.elements.first) && first_element.name == 'include'
      append_line '----'
      node.elements.each do |el|
        append_line %(include::{sourcedir}/#{el.attr 'href'}[])
      end
      append_line '----'
    else
      source_lines = node.text.rstrip.split EOL
      if @delimit_source || (source_lines.detect {|line| line.rstrip.empty?})
        append_line '----'
        append_line (source_lines * EOL)
        append_line '----'
      else
        append_line (source_lines * EOL)
      end
    end
    false
  end

  def visit_example node
    process_example node
  end

  def visit_informalexample node
    process_example node
  end

  def process_example node
    append_blank_line
    append_block_title node
    elements = node.elements.to_a
    if elements.size > 0 && elements.first.name == 'title'
      elements.shift
    end
    if elements.size == 1 && (PARA_TAG_NAMES.include? (child = elements.first).name)
      append_line '[example]'
      # must reset adjoin_next in case block title is placed
      @adjoin_next = false
      append_line (format_text child)
    else
      append_line '===='
      @adjoin_next = true
      proceed node
      @adjoin_next = false
      append_line '===='
    end
    false
  end

  # FIXME wrap this up in a process_block method
  def visit_sidebar node
    append_blank_line
    append_block_title node 
    elements = node.elements.to_a
    # TODO make skipping title a part of append_block_title perhaps?
    if elements.size > 0 && elements.first.name == 'title'
      elements.shift
    end
    if elements.size == 1 && PARA_TAG_NAMES.include?((child = elements.first).name)
      append_line '[sidebar]'
      append_line format_text child
    else
      append_line '****'
      @adjoin_next = true
      proceed node
      @adjoin_next = false
      append_line '****'
    end
    false
  end

  def visit_blockquote node
    append_blank_line
    append_block_title node 
    elements = node.elements.to_a
    # TODO make skipping title a part of append_block_title perhaps?
    if elements.size > 0 && elements.first.name == 'title'
      elements.shift
    end
    if elements.size == 1 && PARA_TAG_NAMES.include?((child = elements.first).name)
      append_line '[quote]'
      append_line format_text child
    else
      append_line '____'
      @adjoin_next = true
      proceed node
      @adjoin_next = false
      append_line '____'
    end
    false
  end

  def visit_table node
    append_blank_line
    append_block_title node
    process_table node
    false
  end

  def visit_informaltable node
    append_blank_line
    process_table node
    false
  end

  def process_table node
    numcols = (node.at_css '> tgroup').attr('cols').to_i
    cols = ('1' * numcols).split('')
    body = node.at_css '> tgroup > tbody'
    row1 = body.at_css '> row'
    row1_cells = row1.elements
    numcols.times do |i|
      next if !(element = row1_cells[i].elements.first)
      case element.name
      when 'literallayout'
        cols[i] = %(#{cols[i]}*l)
      end
    end

    if (frame = node.attr('frame'))
      frame = %(, frame="#{frame}")
    else
      frame = nil
    end
    options = []
    if (head = node.at_css '> tgroup > thead')
      options << 'header'
    end
    if (foot = node.at_css '> tgroup > tfoot')
      options << 'footer'
    end
    options = (options.empty? ? nil : %(, options="#{options * ','}"))
    append_line %([cols="#{cols * ','}"#{frame}#{options}])
    append_line '|==='
    if head
      (head.css '> row > entry').each do |cell|
        append_line %(| #{text cell})
      end
    end
    (node.css '> tgroup > tbody > row').each do |row|
      append_blank_line
      row.elements.each do |cell|
        next if !(element = cell.elements.first)
        if element.text.empty?
          append_line '|'
        else
          append_line %(| #{text cell})
          #case element.name
          #when 'literallayout'
          #  append_line %(|`#{text cell}`)
          #else
          #  append_line %(|#{text cell})
          #end
        end
      end
    end
    if foot
      (foot.css '> row > entry').each do |cell|
        # FIXME needs inline formatting like body
        append_line %(| #{text cell})
      end
    end
    append_line '|==='
    false
  end

  ### Inline node visitors

  def visit_text node
    in_para = PARA_TAG_NAMES.include?(node.parent.name) || node.parent.name == 'phrase'
    is_first = !node.previous_element
    # drop text if empty unless we're processing a paragraph
    unless node.text.rstrip.empty? && !in_para
      text = node.text
      if in_para
        leading_space_match = text.match LeadingSpaceRx
        # strips surrounding endlines and indentation on normal paragraphs
        # TODO factor out this whitespace processing
        text = text.gsub(LeadingEndlinesRx, '')
            .gsub(WrappedIndentRx, @preserve_line_wrap ? EOL : ' ')
            .gsub(TrailingEndlinesRx, '')
        if is_first
          text = text.lstrip
        elsif leading_space_match && !!(text !~ LeadingSpaceRx)
          # QUESTION if leading space was an endline, should we restore the endline or just put a space char?
          text = %(#{leading_space_match[0]}#{text})
        end

        # FIXME sentence-per-line logic should be applied at paragraph block level only
        if @sentence_per_line
          # FIXME move regexp to constant
          text = text.gsub(/(?:^|\b)\.[[:blank:]]+(?!\Z)/, %(.#{EOL}))
        end
      end
      append_text text, true
    end
    false
  end

  def visit_anchor node
    return false if node.parent.name.start_with? 'biblio'
    id = resolve_id node, normalize: @normalize_ids
    append_text %([[#{id}]])
    false
  end

  def visit_link node
    if node.attr 'linkend'
      visit_xref node
    else
      visit_uri node
    end
    false
  end

  def visit_uri node
    url = if node.name == 'ulink'
      node.attr 'url'
    else
      xlink_ns = node.namespaces.find {|(k,v)| v == 'http://www.w3.org/1999/xlink' }.first.split(':', 2).last
      node.attr %(#{xlink_ns}:href)
    end
    prefix = 'link:'
    if url.start_with?('http://') || url.start_with?('https://')
      prefix = nil
    end
    label = text node
    if label.empty? || url == label
      if (ref = @attributes.key(url))
        url = %({#{ref}})
      end
      append_text %(#{prefix}#{url})
    else
      if (ref = @attributes.key(url))
        url = %({#{ref}})
      end
      append_text %(#{prefix}#{url}[#{label}])
    end
    false
  end

  alias :visit_ulink :visit_uri

  # QUESTION detect bibliography reference and autogen label?
  def visit_xref node
    linkend = node.attr 'linkend'
    id = @normalize_ids ? (normalize_id linkend) : linkend
    if (label = format_text node).empty?
      append_text %(<<#{id}>>)
    else
      append_text %(<<#{id},#{lazy_quote label}>>)
    end
    false
  end

  def visit_phrase node
    if node.attr 'role'
      # FIXME for now, double up the marks to be sure we catch it
      append_text %([#{node.attr 'role'}]###{format_text node}##)
    else
      append_text %(#{format_text node})
    end
    false
  end

  def visit_foreignphrase node
    append_text format_text node
  end

  alias :visit_attribution :proceed

  def visit_quote node
    append_text %("`#{format_text node}`")
  end

  def visit_emphasis node
    quote_char = node.attr('role') == 'strong' ? '*' : '_'
    append_text %(#{quote_char}#{format_text node}#{quote_char})
    false
  end

  def visit_remark node
    append_text %(##{format_text node}#)
    false
  end

  def visit_trademark node
    append_text %(#{format_text node}(TM))
    false
  end

  def visit_prompt node
    # TODO remove the space left by the prompt
    #@lines.last.chop!
    false
  end

  def process_path node
    role = 'path'
    #role = case (name = node.name)
    #when 'directory'
    #  'path'
    #when 'filename'
    #  'path'
    #else
    #  name
    #end
    append_text %([#{role}]_#{node.text}_)
    false
  end

  def process_ui node
    name = node.name
    if name == 'guilabel' && (next_node = node.next) &&
        next_node.type == ENTITY_REF_NODE && ['rarr', 'gt'].include?(next_node.name)
      name = 'guimenu'
    end

    case name
    # ex. <menuchoice><guimenu>System</guimenu><guisubmenu>Documentation</guisubmenu></menuchoice>
    when 'menuchoice'
      items = node.children.map {|node|
        if (node.type == ELEMENT_NODE) && ['guimenu', 'guisubmenu', 'guimenuitem'].include?(node.name)
          node.instance_variable_set :@skip, true
          node.text
        end
      }.compact
      append_text %(menu:#{items[0]}[#{items[1..-1] * ' > '}])
    # ex. <guimenu>Files</guimenu> (top-level)
    when 'guimenu'
      append_text %(menu:#{node.text}[])
      # QUESTION when is this needed??
      #items = []
      #while (node = node.next) && ((node.type == ENTITY_REF_NODE && ['rarr', 'gt'].include?(node.name)) ||
      #  (node.type == ELEMENT_NODE && ['guimenu', 'guilabel'].include?(node.name)))
      #  if node.type == ELEMENT_NODE
      #    items << node.text
      #  end
      #  node.instance_variable_set :@skip, true
      #end
      #append_text %([#{items * ' > '}]) 
    when 'guibutton'
      append_text %(btn:[#{node.text}])
    when 'guilabel'
      append_text %([label]##{node.text}#)
    when 'keycap'
      append_text %(kbd:[#{node.text}])
    end
    false
  end

  def process_keyword node
    role, char = case (name = node.name)
    when 'firstterm'
      ['term', '_']
    when 'citetitle'
      ['ref', '_']
    else
      [name, '#']
    end
    append_text %([#{role}]#{char}#{node.text}#{char})
    false
  end

  def process_literal node
    name = node.name
    unless ANONYMOUS_LITERAL_NAMES.include? name
      shortname = case name
      when 'envar'
        'var'
      when 'application'
        'app'
      else
        name.sub 'name', ''
      end
      append_text %([#{shortname}])
    end
    if ((prev_node = node.previous) && prev_node.type == TEXT_NODE && /\p{Word}\Z/ =~ prev_node.text) ||
      ((next_node = node.next) && next_node.type == TEXT_NODE && /\A\p{Word}/ =~ next_node.text)
      append_text %(``#{node.text}``)
    else
      # FIXME be smart about when to use ` vs `` or `+...+`
      append_text %(`#{node.text}`)
    end
    false 
  end

  alias :visit_guiicon :proceed

  def visit_inlinemediaobject node
    src = node.at_css('imageobject imagedata').attr('fileref')
    alt = text_at_css node, 'textobject phrase'
    generated_alt = ::File.basename(src)[0...-(::File.extname(src).length)]
    alt = nil if alt && alt == generated_alt
    append_text %(image:#{src}[#{lazy_quote alt}])
    false
  end

  def visit_mediaobject node
    visit_figure node
  end

  # FIXME share logic w/ visit_inlinemediaobject, which is the same here except no block_title and uses append_text, not append_line
  def visit_figure node
    append_blank_line
    append_block_title node
    if (image_node = node.at_css('imageobject imagedata'))
      src = image_node.attr('fileref')
      alt = text_at_css node, 'textobject phrase'
      generated_alt = ::File.basename(src)[0...-(::File.extname(src).length)]
      alt = nil if alt && alt == generated_alt
      append_blank_line
      append_line %(image::#{src}[#{lazy_quote alt}])
    else
      warn %(Unknown mediaobject <#{node.elements.first.name}>! Skipping.)
    end
    false
  end

  def visit_footnote node
    append_text %(footnote:[#{(text_at_css node, '> para', '> simpara').strip}])
    # FIXME not sure a blank line is always appropriate
    #append_blank_line
    false
  end

  # FIXME blank lines showing up between adjacent index terms
  def visit_indexterm node
    previous_skipped = false
    if @skip.has_key? :indexterm
      skip_count = @skip[:indexterm]
      if skip_count > 0
        @skip[:indexterm] -= 1
        return false
      else
        @skip.delete :indexterm
        previous_skipped = true
      end
    end

    @requires_index = true
    entries = [(text_at_css node, 'primary'), (text_at_css node, 'secondary'), (text_at_css node, 'tertiary')].compact
    #if previous_skipped && (previous = node.previous_element) && previous.name == 'indexterm'
    #  append_blank_line
    #end
    @skip[:indexterm] = entries.size - 1 if entries.size > 1
    append_line %[(((#{entries * ','})))]
    # Only if next word matches the index term do we use double-bracket form
    #if entries.size == 1
    #  append_text %[((#{entries.first}))]
    #else
    #  @skip[:indexterm] = entries.size - 1
    #  append_text %[(((#{entries * ','})))]
    #end
    false
  end

  def visit_pi node
    case node.name
    when 'asciidoc-br'
      append_text ' +'
    when 'asciidoc-hr'
      # <?asciidoc-hr?> will be wrapped in a para/simpara
      append_text '\'' * 3
    end
    false
  end

  def visit_funcsynopsis node
    append_line '[source,c]'
    append_line '----'

    info = node.at_xpath('xmlns:funcsynopsisinfo',
                         {'xmlns' => 'http://docbook.org/ns/docbook'})
    if info
      info.text.strip.each_line do |line|
        append_line line.strip
      end
      append_blank_line
    end

    prototype = node.at_xpath('xmlns:funcprototype',
                              {'xmlns' => 'http://docbook.org/ns/docbook'})
    if prototype
      indent = 0
      first = true
      append_blank_line
      funcdef = prototype.at_xpath('xmlns:funcdef',
                                   {'xmlns' => 'http://docbook.org/ns/docbook'})
      if funcdef
        append_text funcdef.text
        indent = funcdef.text.length + 2
      end

      paramdefs = prototype.xpath('xmlns:paramdef',
                                  {'xmlns' => 'http://docbook.org/ns/docbook'})
      paramdefs.each do |paramdef|
        if first
          append_text ' ('
          first = nil
        else
          append_text ','
          append_line ' ' * indent
        end
        append_text paramdef.text.sub(/\n.*/m, "")
        param = paramdef.at_xpath('xmlns:funcparams',
                                  {'xmlns' => 'http://docbook.org/ns/docbook'})
        append_text " (#{param.text})" if param
      end

      varargs = prototype.at_xpath('xmlns:varargs',
                                   {'xmlns' => 'http://docbook.org/ns/docbook'})
      if varargs
        if first
          append_text ' ('
          first = nil
        else
          append_text ','
          append_line ' ' * indent
        end
        append_text "#{varargs.text}..."
      end

      if first
        append_text ' (void);'
      else
        append_text ');'
      end
    end

    append_line '----'
  end

  def lazy_quote text, seek = ','
    if text && (text.include? seek)
      %("#{text}")
    else
      text
    end
  end

  def unwrap_text text
    text.gsub WrappedIndentRx, ''
  end
end
end
