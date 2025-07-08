/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250708@Winston
	DB: DBCUST.bodb_licensee
	Description: Update discount setting
*/
use bodb_licensee
--Update DiscountGroupId (824, 823) with FromAmount = 0.1
UPDATE LA_DiscountGroupDetail WITH(ROWLOCK, UPDLOCK) 
SET 
	FromAmount = 0.1
WHERE 
	DiscountGroupDetailid in (2747,2748)








