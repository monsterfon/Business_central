namespace DefaultPublisher.MyALItemClassification;

pageextension 50101 ItemCardExt extends 30
{
    layout
    {
        addlast(Content)  // Changed from General to Content – ensure this group exists on the base page.
        {
            field("Item Class"; Rec."Item Class")
            {
                ApplicationArea = All;
                Caption = 'Item Class';
                TableRelation = "Item Class".Code;
                trigger OnValidate()
                begin
                    if Rec.Blocked then
                        Error('Cannot select an Item Class for a blocked item.');
                end;
            }
        }
    }
}