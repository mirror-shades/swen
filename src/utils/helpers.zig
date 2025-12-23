pub fn isBreakChar(char: u8) bool {
    return (char == ' ' or char == '\n' or char == '\r' or char == '\t' or isSymbol(char));
}

pub fn isNumber(char: u8) bool {
    return (char >= '0' and char <= '9');
}

pub fn isFloat(literal: []const u8) bool {
    for (literal) |char| {
        if (char == '.') {
            return true;
        }
    }
    return false;
}

pub fn isSymbol(char: u8) bool {
    return (char == '[' or char == ']' or char == '{' or char == '}' or char == '(' or char == ')' or char == ',' or char == ':' or char == ';' or char == '.');
}

pub fn isIdentifier(char: u8) bool {
    return (char >= 'a' and char <= 'z' or char >= 'A' and char <= 'Z' or char == '_');
}
