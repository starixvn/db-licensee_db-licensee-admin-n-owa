/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeAssignmentUpd]
	@GroupMinFeeID			SMALLINT,
	@LicenseeSettingData	VARCHAR(MAX),
	@OldData				XML				= ''	OUTPUT,
	@ErrCode				INT				= 0		OUTPUT,
	@ErrMsg					VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20200701@Happy
	Task : Update GroupMinFee
	DB: DBCUST.bodb_Licensee

	Revisions:

	Param's Explannation: 
						@LicenseeSettingData = '<Root>
								<LicenseeSetting>
									<PartyID>1</PartyID>
									<IsPrimary>1</IsPrimary>
								</LicenseeSetting>
								<LicenseeSetting>
									<PartyID>2</PartyID>
									<IsPrimary>0</IsPrimary>
								</LicenseeSetting>
							</Root>'
*/
BEGIN
	SET NOCOUNT ON;
	DECLARE @LicenseeSettings TABLE (GroupMinFeeID SMALLINT, PartyID INT, IsPrimary BIT)
	
	IF(@LicenseeSettingData <> '')
	BEGIN
		DECLARE @docHandler INT
		BEGIN TRY
			EXEC sp_xml_preparedocument @docHandler OUTPUT, @LicenseeSettingData
			INSERT INTO @LicenseeSettings(GroupMinFeeID, PartyID, IsPrimary)
			SELECT @GroupMinFeeID, PartyID, IsPrimary
			FROM OPENXML(@docHandler, 'Root/LicenseeSetting')
			WITH(PartyID INT 'PartyID',
					IsPrimary BIT 'IsPrimary')
				
			EXEC sp_xml_removedocument @docHandler
		END TRY
		BEGIN CATCH
			SELECT @ErrMsg = 'Licensee setting data invalid. Please try again.', @ErrCode = 100
			RETURN
		END CATCH;
	END
	
	--A licensee belongs to only 1 group min fee
	DECLARE @HeaderFromDate DATE,
			@HeaderToDate DATE
			
	SELECT @HeaderFromDate = FromDate, @HeaderToDate = ToDate
	FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeID
	--Check if a licensee belongs to a group min fee isnt expired
	IF EXISTS (
		SELECT 1 
		FROM @LicenseeSettings s
			LEFT JOIN dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK) ON s.PartyID = a.PartyID
			INNER JOIN dbo.LA_GroupMinFeeHeader h WITH(NOLOCK) ON a.GroupMinFeeID = h.GroupMinFeeID
		WHERE (@HeaderFromDate <= h.ToDate AND @HeaderToDate >= h.FromDate))
	BEGIN
		SELECT @ErrMsg = 'A licensee belongs to only 1 group min fee.', @ErrCode = 506
		RETURN
	END
	
	--#Region backup
	SET @OldData = (
		SELECT GroupMinFeeID, PartyID, IsPrimary
		FROM dbo.LA_GroupMinFeeAssignment WITH(NOLOCK)
		WHERE GroupMinFeeID = @GroupMinFeeID FOR XML PATH('LicenseeSetting'), ROOT('Root'))
	--#Endregion
	
	--#Region update
	;MERGE dbo.LA_GroupMinFeeAssignment WITH(ROWLOCK, UPDLOCK) AS t
	USING @LicenseeSettings AS s
	ON (t.GroupMinFeeID = s.GroupMinFeeID AND t.PartyID = s.PartyID)
	WHEN MATCHED
		THEN UPDATE SET t.IsPrimary = s.IsPrimary
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(GroupMinFeeID, PartyID, IsPrimary)
				VALUES(s.GroupMinFeeID, s.PartyID, s.IsPrimary);
	
	--A group min fee should have at least 2 payers
	IF EXISTS (SELECT 1 
				FROM dbo.LA_GroupMinFeeAssignment WITH(NOLOCK) 
				WHERE GroupMinFeeID = @GroupMinFeeID 
				HAVING COUNT(PartyID) < 2)
	BEGIN
		SELECT @ErrMsg = 'Should has at least 2 payers in group.', @ErrCode = 506
		RETURN
	END
	
	--A group min fee must have 1 primary licensee.
	IF EXISTS (SELECT 1 
				FROM dbo.LA_GroupMinFeeAssignment WITH(NOLOCK)
				WHERE GroupMinFeeID = @GroupMinFeeID 
				HAVING COUNT(CASE IsPrimary WHEN 1 THEN 1 ELSE NULL END) <> 1)
	BEGIN
		SELECT @ErrMsg = 'Please assign the primary licensee.', @ErrCode = 506
		RETURN
	END
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update LA_GroupMinFeeAssignment failed. Please try again.', @ErrCode = 503
		RETURN
	END
END
GO
