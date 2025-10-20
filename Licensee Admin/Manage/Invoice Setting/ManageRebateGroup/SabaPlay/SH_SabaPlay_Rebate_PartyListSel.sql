/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_SabaPlay_Rebate_PartyListSel]
	@GroupId	SMALLINT = 0,
	@FromDate	DATE = NULL, 
	@ToDate		DATE = NULL
AS
/*  
	  Created: 20251017@Danny [#241642]
	 Task : Manage Rebate On winloss group (SabaPlay)
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20251017@Danny: Create SP [#241642]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @PartyList TABLE(PartyId INT, PartyName VARCHAR(100))
	SELECT op.PartyID, op.PartyName
	FROM OAS_Party op WITH (NOLOCK) 
	INNER JOIN OAS_PartyDetail opd WITH (NOLOCK) ON op.PartyID = opd.PartyID
	WHERE op.PlatformId = 2 AND op.PartyType = 1

	DECLARE @DiscountGroupType TINYINT = 0
	SELECT  @DiscountGroupType = DiscountGroupType FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK) WHERE DiscountGroupId = @GroupId

	IF @GroupId <> 0 AND @DiscountGroupType IN (52) AND @FromDate IS NOT NULL AND @ToDate IS NOT NULL
	BEGIN
		DECLARE @ExistPartyList TABLE (PartyId INT)
		INSERT INTO @ExistPartyList (PartyId)
		SELECT DISTINCT a.PartyId
		FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId			
		WHERE h.DiscountGroupType IN (52) -- Rebate on Lic Fee/WL
			AND h.DiscountGroupType <> @DiscountGroupType
			AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate

		DELETE p
		FROM @PartyList p
			INNER JOIN @ExistPartyList ep ON p.PartyId = ep.PartyId
	END

	-- Return party list
	SELECT PartyId, PartyName
	FROM @PartyList

END
GO