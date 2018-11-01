/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LicenseeDiscountSel]
AS
/*  
	 Created: 20181031@Parsons [#99694]
	 Task : Configure discount settings by currency
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20181031@Parsons: Configure discount settings by currency [#99694]

	 Params:

	 Explannation: EXEC LA_LicenseeDiscountSel
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListNonOfficialSel
	
	;WITH cte_DiscountGroupAssignment AS(
		SELECT MAX(DiscountGroupId) AS DiscountGroupId, PartyID 
		FROM LA_DiscountGroupAssignment WITH(NOLOCK)
		GROUP BY PartyID
	), cte_DiscountSetting AS( 
		SELECT a.PartyID, h.ToDate
		FROM LA_DiscountGroupHeader h WITH(NOLOCK)
		INNER JOIN cte_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId)

	SELECT p.PartyName, ds.ToDate
	FROM @Parties p
	LEFT JOIN cte_DiscountSetting ds ON p.PartyId = ds.PartyID
	WHERE p.ParentId != 0
END
GO