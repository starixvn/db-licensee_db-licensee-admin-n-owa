/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[SH_SabaPlay_SettlementReport_LicenseeListSel]
	 @UserID		INT	   = 0
	,@FunctionKey	NVARCHAR(100)	= ''
AS
/*  Created: 20250403@Danny
	Task : Report - SabaPlay Licensee Settlement Report - Load Licensee dropdown 
	DB: DBLIC.bodb_licensee
		
	Revisions:
		- 20250403@Danny: create new sp
	
	Param's Explanation:



*/
BEGIN
	SET NOCOUNT ON

	DROP TABLE IF EXISTS #userFunctionParty
	CREATE TABLE #userFunctionParty (PartyID INT, UserID INT, FunctionID INT, StatusID TINYINT, PartyName NVARCHAR(100), PlatformId INT, OldRefID INT)

	DECLARE @FunctionID INT, @BillerID INT

	SELECT @BillerID =  PartyId
	FROM dbo.LA_BillerInfo WITH(NOLOCK) WHERE BillerName = 'Reasternhold Limited'

	IF(@FunctionKey = '')
	BEGIN
		SET @FunctionID = 0
	END
	ELSE
	BEGIN
		SELECT @FunctionID = FunctionID FROM LA_Function WITH(NOLOCK) WHERE FunctionKey = @FunctionKey
	END	

	IF (@USERID > 0 AND @FunctionID > 0 ) --get Party List By User and Function
	BEGIN
		INSERT INTO #userFunctionParty(PartyID, UserID, FunctionID, StatusID, PartyName, PlatformId, OldRefID)
		SELECT up.PartyID, Up.UserID, fp.FunctionID, Up.StatusID, op.PartyName, op.PlatformId, op.OldRefID
		FROM dbo.LA_UserParty Up WITH (NOLOCK)
			INNER JOIN OAS_Party op WITH (NOLOCK) ON Up.PartyID = op.PartyID
		    INNER JOIN dbo.LA_UserFunction UF WITH (NOLOCK) ON up.UserID = uf.UserID --permission of user
		    INNER JOIN dbo.LA_FunctionParty FP WITH (NOLOCK) ON up.PartyID = fp.PartyID
			    AND uf.FunctionID = fp.FunctionID --permission of Function - Party
		WHERE up.UserID = @userID
			AND fp.FunctionID = @FunctionID
			AND op.PlatformId IN (2,3)	 AND op.PartyType = 1
	END

	SELECT	t.PartyID, 
			t.PartyName, 
			CASE WHEN t.PlatformId = 2 THEN 9999 ELSE p.ParentID END AS ParentID, 
			CASE WHEN t.PlatformId = 2 THEN 'SabaPlay Licensees' ELSE p.ParentName END AS ParentName,
			CASE WHEN t.PlatformId = 2 THEN t.OldRefID ELSE so.SiteID END OperatorID,
			x.x AS ProductList
	FROM #userFunctionParty t
	LEFT JOIN bodb_licenseeReport.dbo.SabaPlay_Operators so WITH(NOLOCK) ON t.PartyName = so.OWSiteName
	OUTER APPLY 
	(
		SELECT TOP 1 oc.ToParty AS ParentID, op.PartyName + ' Licensees' AS ParentName FROM OAS_ChargeInfo oc WITH(NOLOCK) 
		INNER JOIN dbo.OAS_Party op WITH(NOLOCK) ON oc.ToParty = op.PartyID
		WHERE oc.FromParty = t.PartyID  AND oc.ChargeType = 1 
	) p
	OUTER APPLY
	(
		SELECT 
		(
			SELECT lis.ProductId , sp.ProductName
			FROM LA_InvoiceSetting lis WITH(NOLOCK)
			INNER JOIN bodb_LicenseeReport.dbo.SabaPlay_Products sp WITH(NOLOCK) ON lis.ProductId = sp.ProductID
			WHERE lis.FromPartyId = t.PartyID AND lis.ToPartyId = @BillerID  AND lis.ProductId IS NOT NULL 
			FOR JSON PATH
		) x
	)x
	WHERE 	CASE WHEN t.PlatformId = 2 THEN t.OldRefID ELSE so.SiteID END IS NOT NULL
	ORDER BY CASE WHEN t.PlatformId = 2 THEN 9999 ELSE p.ParentID END, t.PartyName
	
END

