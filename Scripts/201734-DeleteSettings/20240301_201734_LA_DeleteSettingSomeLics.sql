/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20240301@Danny
	DB: DBCUST-bodb_Licensee
	Task: Delete setting some Licensees
*/

USE bodb_licensee

DECLARE @PartyId_999 INT = 999
DECLARE @PartyId_1000 INT = 1000
DECLARE @PartyId_1001 INT = 1001
DECLARE @PartyId_1002 INT = 1002

--DELETE dbo.OAS_Party WITH(ROWLOCK) WHERE PartyId IN ( @PartyId_999, @PartyId_1000, @PartyId_1001, @PartyId_1002)
--DELETE dbo.OAS_PartyDetail  WITH(ROWLOCK) WHERE PartyId IN ( @PartyId_999, @PartyId_1000, @PartyId_1001, @PartyId_1002)

--DELETE l 
--FROM dbo.LA_ChargeInfo_SystemMapping l WITH(ROWLOCK)
--	INNER JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON l.ChargeID = c.ChargeID
--WHERE c.FromParty IN ( @PartyId_999, @PartyId_1000, @PartyId_1001, @PartyId_1002)

--DELETE dbo.OAS_PartyBaseCurrency WITH(ROWLOCK) WHERE PartyId IN ( @PartyId_999, @PartyId_1000, @PartyId_1001,@PartyId_1002)
--DELETE dbo.OAS_ChargeInfo WITH(ROWLOCK) WHERE FromParty IN ( @PartyId_999, @PartyId_1000, @PartyId_1001,@PartyId_1002)
--DELETE dbo.LA_MinFee WITH(ROWLOCK) WHERE PartyID IN ( @PartyId_999, @PartyId_1000, @PartyId_1001,@PartyId_1002)
--DELETE dbo.LA_InvoiceSetting WITH(ROWLOCK) WHERE FromPartyId IN ( @PartyId_999, @PartyId_1000, @PartyId_1001,@PartyId_1002)
--DELETE dbo.LA_UserParty WITH(ROWLOCK) WHERE PartyId IN ( @PartyId_999, @PartyId_1000, @PartyId_1001,@PartyId_1002)
--DELETE dbo.LA_FunctionParty WITH(ROWLOCK) WHERE PartyId IN ( @PartyId_999, @PartyId_1000, @PartyId_1001,@PartyId_1002)


DELETE LA_CombinedGroupAssignment  WITH(ROWLOCK) 
 WHERE PartyId IN ( @PartyId_999, @PartyId_1000, @PartyId_1001, @PartyId_1002) AND GroupId=109