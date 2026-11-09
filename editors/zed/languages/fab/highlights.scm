; fAB highlights in Zed's capture names; ../../../../tree-sitter-fab/queries
; has the same in Helix's. Keep the two in step.

(comment) @comment

(zone_id) @type
(node_id) @constant
(at) @variable.special
(star) @constant.builtin
(edge_id) @function
(attr_id) @property
(type_id) @type.builtin
(class_id) @enum

(string) @string
(math) @string.special
(value) @string.special

[(decl) (defn)] @keyword
[(slash) (marker) (dot) (iden) (cong) (bar)] @operator
(comma) @punctuation.delimiter
["(" ")" "{" "}"] @punctuation.bracket
