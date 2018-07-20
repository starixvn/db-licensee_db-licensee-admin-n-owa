/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Discount_PartiesLaunchingEnoughDays] 
	@PartyIds		VARCHAR(512)	= '', 
	@AreEnoughDays 	BIT				= 1	OUTPUT
AS
/*  
	 Created: 20180719@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180719@Parsons: check parties have been launching enough days [#94282]
	 Params:

	 Explannation: 
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @NumberOfEnougDays INT = 30
	DECLARE @Parties TABLE (PartyId INT)
	
	INSERT INTO @Parties(PartyId)
	SELECT val FROM bodb02.dbo.strSplit(@PartyIds, ',')

	DECLARE @LaunchingDate TABLE(LaunchingDate DATE, PartyId INT)
	;WITH P AS (
		SELECT ci.FromDate, p.PartyID
		FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN @Parties af ON af.PartyId=p.PartyID
		INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping map WITH(NOLOCK) ON map.ChargeID = ci.ChargeID and map.SystemID = 2
		WHERE ci.ProductId NOT IN (SELECT DISTINCT ProductId FROM dbo.LA_Product3rdSub WITH(NOLOCK)) AND p.PartyType IN (1,5)
	)
	INSERT INTO @LaunchingDate(LaunchingDate, PartyId)
	SELECT MIN(FromDate), PartyID FROM P GROUP BY PartyID

	IF (EXISTS(SELECT TOP 1 PartyId
		FROM @LaunchingDate
		WHERE DATEDIFF(DAY, LaunchingDate, GETDATE()) > @NumberOfEnougDays
	))
	BEGIN
		SET @AreEnoughDays = 1
	END
	ELSE
	BEGIN
		SET @AreEnoughDays = 0
	END
	
END
GO
