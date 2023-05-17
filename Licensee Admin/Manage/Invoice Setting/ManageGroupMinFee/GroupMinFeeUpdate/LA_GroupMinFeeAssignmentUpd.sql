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
		- 20200701@Happy: Implement Group Min Fee [#134492]
		- 20230517@Danny: validation on currency when adding new payer [#188014]

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

	DECLARE @LicenseeSettings TABLE (GroupMinFeeID SMALLINT, PartyID INT, IsPrimary BIT, BaseCurrencyID INT, GroupMinFeeCurr INT, PartyName VARCHAR(50))
	DECLARE @GroupMinFeeCurr INT

	SELECT @GroupMinFeeCurr = CurrencyId
	FROM LA_GroupMinFeeDetail WITH(NOLOCK) WHERE GroupMinFeeID = @GroupMinFeeID

	IF(@LicenseeSettingData <> '')
	BEGIN
		DECLARE @docHandler INT
		BEGIN TRY
			EXEC sp_xml_preparedocument @docHandler OUTPUT, @LicenseeSettingData
			INSERT INTO @LicenseeSettings(GroupMinFeeID, PartyID, IsPrimary, PartyName)
			SELECT @GroupMinFeeID, PartyID, IsPrimary, PartyName
			FROM OPENXML(@docHandler, 'Root/LicenseeSetting')
			WITH(PartyID INT 'PartyID',
					IsPrimary BIT 'IsPrimary',
					PartyName VARCHAR(50) 'PartyName')
				
			EXEC sp_xml_removedocument @docHandler
		END TRY
		BEGIN CATCH
			SELECT @ErrMsg = 'Licensee setting data invalid. Please try again.', @ErrCode = 100
			RETURN
		END CATCH;
	END

	-- Get Base Currency Info
	UPDATE t
	SET	 t.BaseCurrencyID = u.BaseCurrencyId,
		 t.GroupMinFeeCurr = @GroupMinFeeCurr
	FROM @LicenseeSettings t
	INNER JOIN OAS_PartyBaseCurrency u WITH(NOLOCK) ON t.PartyID = u.PartyID AND u.FromDate <= GETDATE() AND u.ToDate >= GETDATE()
	
	--A licensee belongs to only 1 group min fee
	DECLARE @HeaderFromDate DATE,
			@HeaderToDate DATE
			
	SELECT @HeaderFromDate = FromDate, @HeaderToDate = ToDate
	FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeID

	--Check if a licensee belongs to a group min fee isnt expired
	IF EXISTS (
		SELECT TOP 1 1 
		FROM @LicenseeSettings s
			INNER JOIN dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK) ON s.PartyID = a.PartyID
			INNER JOIN dbo.LA_GroupMinFeeHeader h WITH(NOLOCK) ON a.GroupMinFeeID = h.GroupMinFeeID
		WHERE (@HeaderFromDate <= h.ToDate AND @HeaderToDate >= h.FromDate AND s.GroupMinFeeID <> a.GroupMinFeeID))
	BEGIN
		SELECT @ErrMsg = 'A licensee belongs to only 1 group min fee.', @ErrCode = 506
		RETURN
	END
		
	--A group min fee should have at least 2 payers
	IF EXISTS (SELECT 1 
				FROM @LicenseeSettings 
				HAVING COUNT(PartyID) < 2)
	BEGIN
		SELECT @ErrMsg = 'Should have at least 2 payers in group.', @ErrCode = 506
		RETURN
	END
	
	--A group min fee must have 1 primary licensee.
	IF EXISTS (SELECT 1 
				FROM @LicenseeSettings
				HAVING COUNT(CASE IsPrimary WHEN 1 THEN 1 ELSE NULL END) <> 1)
	BEGIN
		SELECT @ErrMsg = 'Please assign the primary licensee.', @ErrCode = 506
		RETURN
	END

	-- validation on currency when adding new payer
	IF EXISTS (SELECT 1 
				FROM @LicenseeSettings
				WHERE BaseCurrencyID <> GroupMinFeeCurr)
	BEGIN
		DECLARE @LicenseeList VARCHAR(4000) = ''
		SELECT @LicenseeList = '('+STRING_AGG(PartyName,', ')+')'
		FROM @LicenseeSettings  WHERE BaseCurrencyID <> GroupMinFeeCurr

		SELECT @ErrMsg = 'Cannot save the setting, currency of payers ' + @LicenseeList + ' and group should be the same!' , @ErrCode = 506
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
				VALUES(s.GroupMinFeeID, s.PartyID, s.IsPrimary)
	WHEN NOT MATCHED BY SOURCE AND t.GroupMinFeeID = @GroupMinFeeID
		THEN DELETE;
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update LA_GroupMinFeeAssignment failed. Please try again.', @ErrCode = 503
		RETURN
	END
END
GO