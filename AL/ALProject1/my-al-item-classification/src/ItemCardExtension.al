page 50103 "Item Class List"
{
    PageType = List;
    SourceTable = "Item Class";
    ApplicationArea = All;
    Caption = 'Item Class List';

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field(Code; Rec.Code)
                {
                    Caption = 'Code';
                }
                field(Description; Rec.Description)
                {
                    Caption = 'Description';
                }
                field("Unit Price Increase (%)"; Rec."Unit Price Increase (%)")
                {
                    Caption = 'Unit Price Increase (%)';
                }
            }
        }
    }
}