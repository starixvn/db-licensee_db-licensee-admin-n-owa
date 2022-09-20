/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_LaunchNewProductSel]
	@ProductCode	 VARCHAR(10)
	,@PlayerNameList NVARCHAR(MAX) = ''
	,@ErrCode		 INT = 0 OUTPUT
	,@ErrMsg		 NVARCHAR(1000) = '' OUTPUT
AS
/*
	Created: 20220919@Malcolm
	Task : Launch new licensee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20220919@Malcolm: Launch new Product [RedmineID: #175860]
		
	Param's Explannation: 

*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @ProductId INT
	
	SELECT @PlayerNameList = ISNULL(@PlayerNameList, '')

	SELECT @ProductId = p.ProductID
	FROM dbo.LA_f_GroupProduct('',NULL,NULL) p
	WHERE p.ProductId = p.GroupProductId AND GroupProductCode= @ProductCode

	DECLARE @Party TABLE (PartyID INT, PartyName VARCHAR(100), InvoiceLanguage VARCHAR(7), ErrCode INT)

	INSERT INTO @Party (PartyName)
	SELECT DISTINCT value FROM STRING_SPLIT(@PlayerNameList, ',')

	UPDATE p
		 SET p.PartyID = op.PartyID
		     ,p.InvoiceLanguage = pd.InvoiceLanguage
		     ,p.ErrCode = CASE WHEN op.PartyID IS NULL THEN  1 -- Invalid payer name
							   WHEN op.PartyType <> 1 THEN 2 -- Not Active payer
							   WHEN lp.LicenseeID IS NULL THEN 3 -- Not offered selected product yet
							   WHEN ISNULL(n.IsLaunched, 0) = 1 THEN 4 -- Already launch the selected product
						  ELSE 5 END -- Invalid
	FROM @Party p
		LEFT JOIN dbo.OAS_Party op WITH(NOLOCK) ON op.PartyName = p.PartyName
		LEFT JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = op.PartyID
		LEFT JOIN dbo.Labels l WITH (NOLOCK) ON op.OldRefId = l.LicenseeId
		LEFT JOIN dbo.LicenseeProduct3rd lp WITH(NOLOCK) ON lp.LicenseeID = CASE WHEN ISNULL(pd.IsDeposit, 0) = 0 THEN l.LabelID ELSE op.OldRefID END
		OUTER APPLY (
			SELECT  TOP 1 1 AS IsLaunched 
			FROM dbo.OAS_ChargeInfo c WITH(NOLOCK) 
			WHERE c.FromParty = op.PartyID AND c.ProductID = @ProductId
		) AS n (IsLaunched)

	SELECT *
	FROM @Party
	WHERE ErrCode IS NULL

	IF EXISTS (SELECT 1 FROM @Party WHERE ErrCode IS NOT NULL)
	BEGIN
		;WITH CTE AS (
			SELECT *
			FROM 
		)
	END

END
GO