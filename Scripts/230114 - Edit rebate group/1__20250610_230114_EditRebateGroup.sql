/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250610@Danny
	DB: DBCUST.bodb_Licensee
	Task: Edit rebate group [#230114]
	Description: Edit rebate group
*/

USE bodb_licensee

DECLARE @DiscountGroupID  INT, @PartyID INT

SELECT @DiscountGroupID = DiscountGroupID FROM LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = 'Alek Group May 2025' AND DiscountGroupType = 12
SELECT @PartyID = PartyID FROM OAS_Party WITH(NOLOCK) WHERE PartyName = 'TigerHub'


INSERT INTO LA_DiscountGroupAssignment (DiscountGroupId, PartyID, Remark, IsApplyDiscount, IsSpecialTreatment)
SELECT @DiscountGroupID, @PartyID, NULL, 0, 0


