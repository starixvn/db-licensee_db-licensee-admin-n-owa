/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20220818@Danny
	DB: DBCUST.bodb_licensee
	Description: 
*/
GO

DELETE FROM LA_DiscountGroupAssignment WITH(ROWLOCK, UPDLOCK)
WHERE DiscountGroupID = 549 -- 'N8B_N8G group_Jun2022'
	AND PartyID = 483 --'Bwing (N8B)'


