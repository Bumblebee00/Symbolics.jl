const TypeT = UInt32
const ISINTEGER = TypeT(0)
const SIGNED_OFFSET = TypeT(1)
const SIZE_OFFSET = TypeT(2)

const EMPTY_DIMS = Int[]

struct StructElement
    typ::TypeT
    name::Symbol
    size::Vector{Int}
    function StructElement(::Type{T}, name, size = EMPTY_DIMS) where {T}
        c = encodetyp(T)
        c == typemax(TypeT) && error("Cannot handle type $T")
        new(c, name, size)
    end
end

_sizeofrepr(typ::TypeT) = typ >> SIZE_OFFSET
sizeofrepr(s::StructElement) = _sizeofrepr(s.typ)
Base.size(s::StructElement) = s.size
Base.length(s::StructElement) = prod(size(s))
Base.nameof(s::StructElement) = s.name
function Base.show(io::IO, s::StructElement)
    print(io, nameof(s), "::", decodetyp(s.typ))
    if length(s) > 1
        print(io, "::(", join(size(s), " × "), ")")
    end
end

function encodetyp(::Type{T}) where {T}
    typ = zero(UInt32)
    if T <: Integer
        typ |= TypeT(1) << ISINTEGER
        if T <: Signed
            typ |= TypeT(1) << SIGNED_OFFSET
        elseif !(T <: Unsigned)
            return typemax(TypeT)
        end
    elseif !(T <: AbstractFloat)
        return typemax(TypeT)
    end
    typ |= TypeT(sizeof(T)) << SIZE_OFFSET
end

function decodetyp(typ::TypeT)
    siz = TypeT(8) * (typ >> SIZE_OFFSET)
    if !iszero(typ & (TypeT(1) << ISINTEGER))
        if !iszero(typ & TypeT(1) << SIGNED_OFFSET)
            siz == 8 ? Int8 :
            siz == 16 ? Int16 :
            siz == 32 ? Int32 :
            siz == 64 ? Int64 :
            error("invalid type $(typ)!")
        else # unsigned
            siz == 8 ? UInt8 :
            siz == 16 ? UInt16 :
            siz == 32 ? UInt32 :
            siz == 64 ? UInt64 :
            error("invalid type $(typ)!")
        end
    else # float
        siz == 16 ? Float16 :
        siz == 32 ? Float32 :
        siz == 64 ? Float64 :
        error("invalid type $(typ)!")
    end
end

struct Struct
    v::Vector{StructElement}
end

function Base.getproperty(s::Struct, name::Symbol)
    v = getfield(s, :v)
    idx = findfirst(x -> nameof(x) == name, v)
    idx === nothing && error("no field $name in struct")
    SymbolicUtils.term(getfield, s, idx, type = Real)
end

function Base.setproperty!(s::Struct, name::Symbol, x)
    v = getfield(s, :v)
    idx = findfirst(x -> nameof(x) == name, v)
    idx === nothing && error("no field $name in struct")
    type = SymbolicUtils.symtype(x)
    SymbolicUtils.term(setfield!, s, idx, x; type)
end

# We cannot precisely derive the type after `getfield` due to SU limitations,
# so give up and just say Real.
SymbolicUtils.promote_symtype(::typeof(getfield), ::Type{<:Struct}, _...) = Real
SymbolicUtils.promote_symtype(::typeof(setfield!), ::Type{<:Struct}, _, ::Type{T}) where T = T
