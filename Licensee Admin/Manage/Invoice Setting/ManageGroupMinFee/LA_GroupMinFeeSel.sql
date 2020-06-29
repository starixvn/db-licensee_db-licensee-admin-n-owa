/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

CREATE PROCEDURE [dbo].[LA_GroupMinFeeSel]
	 @GroupMinFeeId	INT	= 0	
AS
/*  
	 Created: 20200629@Happy
	 Task : Get all groups min fee or get by ID
	 DB: DBLIC.bodb_Licensee  
   
	 Revisions:
		 
	 Params:
		- @GroupMinFeeId:
			= 0: get all group
			<> 0: specific group
	 Example:
		EXEC dbo.LA_GroupMinFeeSel @GroupMinFeeId = 0 
*/
BEGIN
	SET NOCOUNT ON;
	
	DECLARE @MinFeeType TINYINT = 1
	DECLARE @Result AS TABLE (GroupMinFeeID SMALLINT, GroupName NVARCHAR(110), NumberOfPayers INT, PayerList VARCHAR(1000), FromDate DATE, ToDate DATE, GroupMinFee MONEY, PrimaryLicensee VARCHAR(50))

	INSERT INTO @Result(GroupMinFeeID , GroupName, NumberOfPayers, FromDate, ToDate)
	SELECT h.GroupMinFeeID AS GroupMinFeeID
			,h.Name AS GroupName
			,COUNT(a.PartyID) AS NumberOfPayers
			,h.FromDate AS FromDate
			,h.ToDate AS ToDate
	FROM dbo.LA_GroupMinFeeHeader h WITH(NOLOCK)
		LEFT JOIN dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK) ON h.GroupMinFeeID = a.GroupMinFeeID
	WHERE (@GroupMinFeeID=0 OR h.GroupMinFeeID = @GroupMinFeeID)
	GROUP BY h.GroupMinFeeID, h.Name, h.FromDate, h.ToDate
	
	-- Update PayerList column
	UPDATE r
	SET r.PayerList = STUFF((
				SELECT ', ' + CAST(CASE WHEN ISNULL(pd.BrandName, '') != '' THEN pd.BrandName ELSE p.PartyName END AS VARCHAR)
				FROM dbo.LA_GroupMinFeeAssignment mfa WITH (NOLOCK)
					LEFT JOIN dbo.OAS_Party p WITH (NOLOCK) ON mfa.PartyID = p.PartyID
					LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
				WHERE r.GroupMinFeeID = mfa.GroupMinFeeID				
				FOR XML PATH ('')), 1, 2, '') 			
	FROM @Result r
	
	--Update GroupMinFee column
	;WITH cte_GroupMinFee AS(
		SELECT TOP(1) WITH TIES mfd.GroupMinFeeID, mfd.MinimumFee AS GroupMinFee
		FROM dbo.LA_GroupMinFeeDetail mfd 
		WHERE (@GroupMinFeeId = 0 OR mfd.GroupMinFeeID = @GroupMinFeeId)
		ORDER BY ROW_NUMBER() OVER(PARTITION BY mfd.GroupMinFeeID order by mfd.ToDate DESC))
	UPDATE r
	SET r.GroupMinFee = mf.GroupMinFee
	FROM @Result r
	LEFT JOIN cte_GroupMinFee mf on mf.GroupMinFeeID = r.GroupMinFeeID
			
	--Update PrimaryLicensee column
	;WITH cte_PrimaryLicensee AS(
		SELECT mfa.GroupMinFeeID, p.PartyName AS PrimaryLicensee
		FROM dbo.LA_GroupMinFeeAssignment mfa
		INNER JOIN dbo.OAS_Party p ON p.PartyID = mfa.PartyID
		WHERE mfa.IsPrimary = 1 AND (@GroupMinFeeId = 0 OR mfa.GroupMinFeeID = @GroupMinFeeId))
	UPDATE r
	SET r.PrimaryLicensee = pm.PrimaryLicensee
	FROM @Result r
	LEFT JOIN cte_PrimaryLicensee pm on pm.GroupMinFeeID = r.GroupMinFeeID
			
	SELECT * FROM @Result
END
GO
