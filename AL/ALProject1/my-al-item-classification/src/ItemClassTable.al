table 50101 "Item Class"
{
    DataClassification = ToBeClassified;

    fields
    {
        field(1; "Code"; Code[20])
        {
            Caption = 'Item Class Code';
            NotBlank = true;
        }
        field(2; "Description"; Text[100])
        {
            Caption = 'Description';
        }
        field(3; "Unit Price Increase (%)"; Decimal)
        {
            Caption = 'Unit Price Increase (%)';
            DecimalPlaces = 2;
        }
    }

    keys
    {
        key(PK; "Code")
        {
            Clustered = true;
        }
    }
}