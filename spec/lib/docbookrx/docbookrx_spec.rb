require 'spec_helper'

describe 'Conversion' do
  it 'should create a document header with title, author and attributes' do
    input = <<-EOS
<?xml version="1.0" encoding="UTF-8"?>
<book xmlns="http://docbook.org/ns/docbook">
<info>
<title>Document Title</title>
<author>
<firstname>Doc</firstname>
<surname>Writer</surname>
<email>doc@example.com</email>
</author>
</info>
<section>
<title>First Section</title>
<para>content</para>
</section>
</book>
    EOS

    expected = <<-EOS.rstrip
= Document Title
Doc Writer <doc@example.com>
:doctype: book
:sectnums:
:toc: left
:icons: font
:experimental:

== First Section

content
    EOS

    output = Docbookrx.convert input

    expect(output).to eq(expected)
  end

  it 'should convert guimenu element to menu macro' do
    input = <<-EOS
<para xmlns="http://docbook.org/ns/docbook">File operations are found in the <guimenu>File</guimenu> menu.</para>
    EOS

    expected = 'menu:File[]'

    output = Docbookrx.convert input

    expect(output).to include(expected)
  end

  it 'should convert menuchoice element to menu macro' do
    input = <<-EOS
<para xmlns="http://docbook.org/ns/docbook">Select <menuchoice><guimenu>File</guimenu><guisubmenu>Open Terminal</guisubmenu><guimenuitem>Default</guimenuitem></menuchoice>.</para>
    EOS

    expected = 'menu:File[Open Terminal > Default]'

    output = Docbookrx.convert input

    expect(output).to include(expected)
  end

  it 'should convert link element to uri macro' do
    input = <<-EOS
<para xmlns="http://docbook.org/ns/docbook" xmlns:xlink="http://www.w3.org/1999/xlink">Read about <link xlink:href="http://en.wikipedia.org/wiki/Object-relational_mapping">Object-relational mapping</link> on Wikipedia.</para>
    EOS

    expected = 'Read about http://en.wikipedia.org/wiki/Object-relational_mapping[Object-relational mapping] on Wikipedia.'

    output = Docbookrx.convert input

    expect(output).to include(expected)
  end

  it 'should convert uri element to uri macro' do
    input = <<-EOS
<para xmlns="http://docbook.org/ns/docbook" xmlns:xlink="http://www.w3.org/1999/xlink">Read about <uri xlink:href="http://en.wikipedia.org/wiki/Object-relational_mapping">Object-relational mapping</uri> on Wikipedia.</para>
    EOS

    expected = 'Read about http://en.wikipedia.org/wiki/Object-relational_mapping[Object-relational mapping] on Wikipedia.'

    output = Docbookrx.convert input

    expect(output).to include(expected)
  end

  it 'should convert ulink element to uri macro' do
    input = <<-EOS
<!DOCTYPE para PUBLIC "-//OASIS//DTD DocBook XML V4.5//EN" "http://www.oasis-open.org/docbook/xml/4.5/docbookx.dtd">
<para xmlns="http://docbook.org/ns/docbook">Read about <ulink url="http://en.wikipedia.org/wiki/Object-relational_mapping">Object-relational mapping</ulink> on Wikipedia.</para>
    EOS

    expected = 'Read about http://en.wikipedia.org/wiki/Object-relational_mapping[Object-relational mapping] on Wikipedia.'

    output = Docbookrx.convert input

    expect(output).to include(expected)
  end

  it 'should use attribute refence for uri if matching uri attribute is present' do
    input = <<-EOS
<para xmlns="http://docbook.org/ns/docbook" xmlns:xlink="http://www.w3.org/1999/xlink">Read about <uri xlink:href="http://en.wikipedia.org/wiki/Object-relational_mapping">Object-relational mapping</uri> on Wikipedia.</para>
    EOS

    expected = 'Read about {uri-orm}[Object-relational mapping] on Wikipedia.'

    output = Docbookrx.convert input, attributes: {
      'uri-orm' => 'http://en.wikipedia.org/wiki/Object-relational_mapping'
    }

    expect(output).to include(expected)
  end

  it 'should convert xref element to xref' do
    input = <<-EOS
<para xmlns="http://docbook.org/ns/docbook" xmlns:xlink="http://www.w3.org/1999/xlink">See <xref linkend="usage"/> for more information.</para>
    EOS

    expected = '<<usage>>'

    output = Docbookrx.convert input, normalize_ids: false

    expect(output).to include(expected)
  end

  it 'should use explicit label on xref if provided' do
    input = <<-EOS
<para xmlns="http://docbook.org/ns/docbook" xmlns:xlink="http://www.w3.org/1999/xlink">See <xref linkend="usage">Usage</xref> for more information.</para>
    EOS

    expected = '<<usage,Usage>>'

    output = Docbookrx.convert input, normalize_ids: false

    expect(output).to include(expected)
  end

  it 'should convert itemized list to unordered list' do
    input = <<-EOS
<itemizedlist xmlns="http://docbook.org/ns/docbook">
<listitem>
<para>Apples</para>
</listitem>
<listitem>
<para>Oranges</para>
</listitem>
<listitem>
<para>Bananas</para>
</listitem>
</itemizedlist>
    EOS

    expected = <<-EOS.rstrip
* Apples
* Oranges
* Bananas
    EOS

    output = Docbookrx.convert input

    expect(output).to include(expected)
  end

  it 'should convert orderedlist to unordered list' do
    input = <<-EOS
<orderedlist xmlns="http://docbook.org/ns/docbook">
<listitem>
<para>Apples</para>
</listitem>
<listitem>
<para>Oranges</para>
</listitem>
<listitem>
<para>Bananas</para>
</listitem>
</orderedlist>
    EOS

    expected = <<-EOS.rstrip
. Apples
. Oranges
. Bananas
    EOS

    output = Docbookrx.convert input

    expect(output).to include(expected)
  end

  it 'should convert various types to anonymous literal' do
    input = <<-EOS
<para>
<code>Apples</code>, <command>oranges</command>, <computeroutput>bananas</computeroutput>, <database>pears</database>, <function>grapes</function>, <literal>mangos</literal>, <tag>kiwis</tag>, and <userinput>persimmons</userinput>.
</para>
    EOS

    expected = <<-EOS.rstrip
`Apples`, `oranges`, `bananas`, `pears`, `grapes`, `mangos`, `kiwis`, and `persimmons`.
    EOS

    output = Docbookrx.convert input

    expect(output).to include(expected)
  end

  it 'should convert quote to double quoted text' do
    input = '<para><quote>Apples</quote></para>'

    expected = '"`Apples`"'

    output = Docbookrx.convert input

    expect(output).to include(expected)
  end
end
