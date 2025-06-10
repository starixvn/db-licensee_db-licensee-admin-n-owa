/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250610@Winston
	DB: DBCUST.bodb_licensee
	Description: Update discount setting
*/

--Delete DiscountGroupId (841, 840) 
DELETE FROM LA_DiscountGroupHeader WITH(ROWLOCK, UPDLOCK)
WHERE DiscountGroupId  in (841, 840) 

DELETE FROM LA_DiscountGroupDetail WITH(ROWLOCK, UPDLOCK)
WHERE DiscountGroupId  in (841, 840) 

DELETE FROM LA_DiscountGroupCurrency WITH(ROWLOCK, UPDLOCK)
WHERE DiscountGroupId  in (841, 840) 

DELETE FROM LA_DiscountGroupProduct WITH(ROWLOCK, UPDLOCK)
WHERE DiscountGroupId  in (841, 840) 

DELETE FROM LA_DiscountGroupAssignment WITH(ROWLOCK, UPDLOCK)
WHERE DiscountGroupId  in (841, 840) 

--Update DiscountGroupId (824, 823) Todate = '2050-01-01'
UPDATE LA_DiscountGroupHeader WITH(ROWLOCK, UPDLOCK) 
SET 
	DiscountGroupName = 'Metasoft group_Others_Apr2025',
	ToDate = '2050-01-01' 
WHERE 
	DiscountGroupId  in (824)

UPDATE LA_DiscountGroupHeader WITH(ROWLOCK, UPDLOCK) 
SET 
	DiscountGroupName = 'Metasoft group_VND_Apr2025',
	ToDate = '2050-01-01' 
WHERE 
	DiscountGroupId  in (823)







