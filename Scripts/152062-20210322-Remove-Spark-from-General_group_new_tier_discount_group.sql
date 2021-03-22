/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210322@Parsons
	DB: DBCUST.bodb_licensee
	Description: Remove-Spark-from-General_group_new_tier_discount_group [#152062]
*/

USE bodb_licensee
GO

DELETE LA_DiscountGroupAssignment WITH (ROWLOCK, UPDLOCK)
WHERE DiscountGroupId = 284 AND PartyID = 404

DELETE LA_DiscountGroupCurrency WITH (ROWLOCK, UPDLOCK)
WHERE DiscountGroupId = 284 AND PartyID = 404