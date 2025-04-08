/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250408@Winston
	DB: DBCUST.bodb_licensee
	Description: 
*/

USE bodb_licensee
GO

INSERT INTO LA_DiscountGroupAssignment (DiscountGroupId,	PartyID,	Remark,	IsApplyDiscount,	IsSpecialTreatment)
SELECT 820,1267,Null, 0, 0



