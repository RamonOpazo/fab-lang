; fAB highlights, in the capture names Helix and Neovim share. They follow
; fab-lsp's semantic tokens: a diagram, a node, an edge, a descriptor, a
; type, a class, a value.

(comment) @comment

(zone_id) @namespace
(node_id) @constant
(star) @constant.builtin
(edge_id) @function
(attr_id) @attribute
(type_id) @type
(class_id) @type.enum

(string) @string
(math) @string.special
(value) @string.special

[(decl) (defn) (then)] @keyword.operator
[(slash) (marker) (dot) (iden) (cong) (bar)] @operator
(comma) @punctuation.delimiter
["(" ")" "{" "}"] @punctuation.bracket
