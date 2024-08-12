/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240812@Danny
	DB: DBCUST.bodb_licensee
	Description: Update payment info
*/

DECLARE @BHC_billerID INT, @ZL_billerID INT, @JS_billerID INT

SELECT @BHC_billerID = PartyID FROM LA_BillerInfo WITH(NOLOCK) WHERE BillerNameAbbreviation = 'BHC'
SELECT @ZL_billerID = PartyID FROM LA_BillerInfo WITH(NOLOCK) WHERE BillerNameAbbreviation = 'ZL'
SELECT @JS_billerID = PartyID FROM LA_BillerInfo WITH(NOLOCK) WHERE BillerNameAbbreviation = 'JS'


UPDATE  LA_Payment WITH(ROWLOCK, UPDLOCK)
SET BillerId = CASE WHEN  PaymentNo LIKE 'BHC %'  THEN @BHC_billerID 
                    WHEN  PaymentNo LIKE 'ZL %'  THEN @ZL_billerID 
					WHEN  PaymentNo LIKE 'JCS %'  THEN @JS_billerID 
					WHEN  PaymentNo LIKE 'BCH %'  THEN @BHC_billerID 
					END
WHERE BillerId IS NULL



UPDATE LA_Payment WITH(ROWLOCK, UPDLOCK) SET StatusId = -1 WHERE PaymentId = 1740




