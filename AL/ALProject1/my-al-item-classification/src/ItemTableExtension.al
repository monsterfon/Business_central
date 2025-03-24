tableextension 50101 ItemTableExt extends 27
{
    fields
    {
        field(50100; "Item Class"; Code[20])
        {
            Caption = 'Item Class';
            TableRelation = "Item Class".Code;
        }
    }
}