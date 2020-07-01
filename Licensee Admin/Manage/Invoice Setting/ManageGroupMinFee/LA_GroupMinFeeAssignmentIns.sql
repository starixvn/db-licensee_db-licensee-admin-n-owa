/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeAssignmentIns]
	@GroupMinFeeID			SMALLINT,
	@LicenseeSettingData	VARCHAR(MAX),
	@ErrorCode				INT				= 0		OUTPUT,
	@ErrorMsg				VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20200630@Happy
	Task : Insert new GroupMinFee
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
	
	DECLARE @LicenseeSettings TABLE (PartyID INT, IsPrimary BIT)
	
	IF(@LicenseeSettingData <> '')
	BEGIN
		DECLARE @docHandler INT
		
		BEGIN TRY
			EXEC sp_xml_preparedocument @docHandler OUTPUT, @LicenseeSettingData
			INSERT INTO @LicenseeSettings(PartyID, IsPrimary)
			SELECT PartyID, IsPrimary
			FROM OPENXML(@docHandler, 'Root/LicenseeSetting')
			WITH(PartyID INT 'PartyID',
					IsPrimary BIT 'IsPrimary')
				
			EXEC sp_xml_removedocument @docHandler
		END TRY
		BEGIN CATCH
			SELECT @ErrorMsg = 'Licensee setting data invalid. Please try again.', @ErrorCode = 100
			RETURN
		END CATCH;
	END
	
	--A licensee belongs to only 1 group min fee
	DECLARE @HeaderFromDate DATE,
			@HeaderToDate DATE
			
	SELECT @HeaderFromDate = FromDate, @HeaderToDate = ToDate
	FROM dbo.LA_GroupMinFeeHeader
	WHERE GroupMinFeeID = @GroupMinFeeID
	
	IF EXISTS (
		SELECT 1 FROM @LicenseeSettings 
		WHERE PartyID IN 
					(SELECT mfa.PartyID 
						FROM dbo.LA_GroupMinFeeAssignment mfa WITH(NOLOCK)
							INNER JOIN dbo.LA_GroupMinFeeHeader mfh WITH(NOLOCK) ON mfa.GroupMinFeeID = mfh.GroupMinFeeID 
						WHERE @HeaderFromDate <= mfh.ToDate AND @HeaderToDate >= mfh.FromDate))
	BEGIN
		SELECT @ErrorMsg = 'A licensee belongs to only 1 group min fee.', @ErrorCode = 506
		RETURN
	END
	
	--A group min fee should have at least 2 payers
	IF EXISTS (SELECT 1 FROM @LicenseeSettings HAVING COUNT(PartyID) < 2)
	BEGIN
		SELECT @ErrorMsg = 'Should has at least 2 payers in group.', @ErrorCode = 506
		RETURN
	END
	
	--A group min fee must have 1 primary licensee.
	IF EXISTS (SELECT 1 FROM @LicenseeSettings HAVING COUNT(CASE IsPrimary WHEN 1 THEN 1 ELSE NULL END) <> 1)
	BEGIN
		SELECT @ErrorMsg = 'Please assign the primary licensee.', @ErrorCode = 506
		RETURN
	END
	
	INSERT INTO dbo.LA_GroupMinFeeAssignment(GroupMinFeeID, PartyID, IsPrimary)
	SELECT @GroupMinFeeID, PartyID, IsPrimary
	FROM @LicenseeSettings
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrorMsg = 'Insert LA_GroupMinFeeAssignment failed. Please try again.', @ErrorCode = 503
		RETURN
	END
END
GO
