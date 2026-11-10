/**
 * fAB's Tree-sitter grammar, for editors: highlighting, folding, selection.
 *
 * Shallow on purpose. spec/grammar.ebnf is the grammar, and fab-core's
 * parser and analyser own its structure; this one reads the tokens by sort,
 * statements and their heads, groups and blocks, and leaves chains flat, so
 * that it changes only when the tokens or the statement forms do.
 *
 * As in fAB, a line end ends a statement, even inside ( ), and inside { } it
 * is whitespace, at any depth.
 */

// A name's body: letters, digits, _, ' and anything non-ASCII.
const body = /[A-Za-z0-9_'\u0080-\u{10FFFF}]*/u.source;
const hyphenated = /[A-Za-z0-9_'\-\u0080-\u{10FFFF}]*/u.source;

module.exports = grammar({
  name: 'fab',

  extras: $ => [/[ \t\r]/, $.comment],

  word: $ => $.edge_id,

  rules: {
    program: $ => seq(
      optional($.statement),
      repeat(seq($._eol, optional($.statement))),
    ),

    _eol: _ => '\n',

    // A declaration (::), a naming (:=), a case (:>), or a description (no
    // operator).
    statement: $ => seq(
      field('head', repeat1($._element)),
      optional(seq(
        field('operator', choice($.decl, $.defn, $.then)),
        field('body', repeat(choice($._element, $.bar, $.comma))),
      )),
    ),

    // Inside a group, line ends end the statement; inside a block they don't.
    group: $ => seq('(', repeat(choice($._element, $.comma, $.decl, $.defn)), ')'),
    _wide_group: $ => seq('(', repeat(choice($._wide_element, $.comma, $.decl, $.defn, $._eol)), ')'),
    block: $ => seq(
      '{',
      repeat(choice($._wide_element, $.comma, $.bar, $.decl, $.defn, $._eol)),
      '}',
    ),

    _element: $ => choice($._token, $.group, $.block),
    _wide_element: $ => choice($._token, alias($._wide_group, $.group), $.block),

    _token: $ => choice(
      $.zone_id, $.node_id, $.edge_id, $.attr_id, $.type_id, $.class_id,
      $.star, $.string, $.math, $.value,
      $.slash, $.marker, $.dot, $.iden, $.cong,
    ),

    zone_id: _ => new RegExp('[A-Z]' + body, 'u'),
    node_id: _ => new RegExp('#[A-Z]' + body, 'u'),
    edge_id: _ => new RegExp('[a-z_\\u0080-\\u{10FFFF}]' + body, 'u'),
    attr_id: _ => new RegExp(':[a-z]' + hyphenated, 'u'),
    type_id: _ => new RegExp(':[A-Z]' + body, 'u'),
    class_id: _ => new RegExp('&[a-z]' + hyphenated, 'u'),

    string: _ => /"([^"\\\n]|\\.)*"/,
    math: _ => /\$([^$\\\n]|\\.)*\$/,
    // One opaque token: no whitespace, brackets, parentheses or commas.
    value: _ => /\[[^\s\[\]\(\),]*\]/,

    star: _ => '*',
    slash: _ => '/',
    marker: _ => choice('+', '?', '!'),
    dot: _ => '.',
    iden: _ => '==',
    cong: _ => '~=',
    decl: _ => '::',
    defn: _ => ':=',
    then: _ => ':>',
    bar: _ => '|',
    comma: _ => ',',

    comment: _ => token(seq('//', /[^\n]*/)),
  },
});
