/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
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
		- 20190603@Parsons: Return group name when exporting licensee list & discount setting [#114558]

	 Params:

	 Explannation: EXEC LA_LicenseeDiscountSel
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	;WITH cte_DiscountGroupAssignment AS(
		SELECT MAX(h.DiscountGroupId) AS DiscountGroupId, PartyID 
		FROM LA_DiscountGroupAssignment a WITH(NOLOCK)
		INNER JOIN LA_DiscountGroupHeader h WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
		WHERE h.DiscountGroupType IN (1, 3, 11, 13)
		GROUP BY PartyID
	), cte_DiscountSetting AS( 
		SELECT a.PartyID, h.DiscountGroupName, h.ToDate
		FROM LA_DiscountGroupHeader h WITH(NOLOCK)
		INNER JOIN cte_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
		WHERE h.DiscountGroupType IN (1, 3, 11, 13))

	SELECT ds.DiscountGroupName, p.PartyName, ds.ToDate
	FROM @Parties p
	LEFT JOIN cte_DiscountSetting ds ON p.PartyId = ds.PartyID
	WHERE p.ParentId != 0
	ORDER BY ds.DiscountGroupName DESC
END
GO